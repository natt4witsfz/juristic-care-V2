-- ============================================================================
-- Juristic Care — Stage 2: Server-enforced job workflow
-- Plan: docs/audit/14-strategy-b-rebuild-plan.md §3 (Stage 2), Amendment 1.
-- Contract: docs/audit/15-job-domain-rpc-contract.md (signatures unchanged).
--
-- Replaces the Stage 1 fail-closed stubs with enforced bodies:
--   1. Workflow helpers: Asia/Bangkok date normalization, text sanitization,
--      the single legal-transition table, evidence validation, the shared
--      client read shape.
--   2. _create_job_internal — the one normalized creation path shared by
--      create_job and ingest_google_form_submission (Amendment 1).
--   3. create_job — authenticated WebApp intake; server-generated JC- id and
--      bcrypt close PIN; idempotency key support.
--   4. assign_job — admin / assignment-capable users; open|working → received.
--   5. update_job_status — legal transitions only; PIN required for
--      completed; noPinAvailable forces pending_inspection +
--      waiting_owner_or_admin_verification; evidence (1–3 photos) enforced;
--      nextUpdateDate only overwritten when the key is present (DB-03).
--   6. verify_job_completion — admin/co-admin, assigner, or reporting room's
--      resident account; never the mere assignee.
--   7. ingest_google_form_submission — single transaction: idempotent by
--      external_id, submission row, exactly one raw=true job, timeline,
--      audit; retry returns the existing job; rollback on any failure.
--      The Form trigger stays DISABLED until Stage 7.
--   8. get_app_bootstrap — jobs are NEVER served from app_snapshots; the
--      'jobs' key is always rebuilt from the relational read path.
--
-- Every transition writes job_timeline AND audit_logs in the same
-- transaction. job_timeline/audit_logs stay client-immutable (no client
-- write privilege or policy; audit_logs additionally has explicit
-- no-update/no-delete policies from v1).
-- Frontend, Edge Functions, Form trigger, SUPABASE_ENABLED: untouched.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Workflow helpers (internal — EXECUTE revoked from all client roles)
-- ----------------------------------------------------------------------------

-- Normalize any incoming date/timestamp string to an Asia/Bangkok calendar
-- date so a near-midnight UTC timestamp never lands on the wrong day.
create or replace function public._bkk_date(p_value text)
returns date
language plpgsql
stable
set search_path = public
as $$
begin
  if p_value is null or btrim(p_value) = '' then
    return null;
  end if;
  if p_value ~ '^\d{4}-\d{2}-\d{2}$' then
    return p_value::date;
  end if;
  return (p_value::timestamptz at time zone 'Asia/Bangkok')::date;
exception when others then
  raise exception 'INVALID_INPUT'
    using detail = 'Unparseable date value', errcode = 'P0001';
end $$;

create or replace function public._bkk_today()
returns date
language sql
stable
set search_path = public
as $$
  select (now() at time zone 'Asia/Bangkok')::date
$$;

-- Server-side text sanitization: strip NULs, trim, enforce a length cap.
create or replace function public._clean_text(p_value text, p_max int)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v text;
begin
  if p_value is null then
    return null;
  end if;
  v := btrim(replace(p_value, chr(0), ''));
  if v = '' then
    return null;
  end if;
  if char_length(v) > p_max then
    raise exception 'INVALID_INPUT'
      using detail = format('Text field exceeds %s characters', p_max),
            errcode = 'P0001';
  end if;
  return v;
end $$;

-- The single legal-transition table (plan §3 Stage 2). Vocabulary mirrors the
-- frontend exactly (app.js statuses): open, received, pending_inspection,
-- inspected_waiting_repair, repaired_follow_up, temporary_waiting_parts,
-- completed, rejected. completed/rejected are terminal. A same-to-same
-- transition within the working set is a legal progress update.
create or replace function public._is_legal_job_transition(p_from text, p_to text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select case
    when p_from in ('completed', 'rejected') then false      -- terminal
    when p_to = 'open' then false                            -- never back to open
    when p_from = 'open' then p_to in ('received', 'rejected')
    when p_from in ('received', 'pending_inspection', 'inspected_waiting_repair',
                    'repaired_follow_up', 'temporary_waiting_parts')
      then p_to in ('received', 'pending_inspection', 'inspected_waiting_repair',
                    'repaired_follow_up', 'temporary_waiting_parts',
                    'completed', 'rejected')
    else false
  end
$$;

-- Client read shape for a single job. MUST stay key-for-key identical to
-- list_jobs_for_current_user() (Stage 1): payload first, then ALL
-- authoritative relational columns, nulls NOT stripped, so a relational NULL
-- always removes the authority of a stale payload value.
create or replace function public._job_read_jsonb(j public.jobs)
returns jsonb
language sql
stable
set search_path = public
as $$
  select j.payload || jsonb_build_object(
           'id',             j.id,
           'source',         j.source,
           'roomId',         j.room_id,
           'reportedBy',     j.reported_by,
           'assignedBy',     j.assigned_by,
           'assignee',       j.assignee_id,
           'status',         j.status,
           'subStatus',      j.sub_status,
           'mainCategory',   j.main_category,
           'category',       j.category,
           'priority',       j.priority,
           'jobDate',        j.job_date,
           'dueDate',        j.due_date,
           'nextUpdateDate', j.next_update_date,
           'sharePublic',    j.share_public,
           'raw',            j.raw,
           'legacyId',       j.legacy_id,
           'importBatchId',  j.import_batch_id,
           'completedAt',    j.completed_at,
           'createdAt',      j.created_at,
           'updatedAt',      j.updated_at
         )
$$;

-- Evidence validation + persistence. p_attachments: jsonb array of
-- {objectPath, originalName, mimeType, sizeBytes}. Enforces the frontend
-- rules server-side: p_min..3 photos, <=5MB each, image mime types only.
-- Inserts job_attachments rows tied to the timeline event.
create or replace function public._store_job_evidence(
  p_job_id text,
  p_timeline_id uuid,
  p_actor_id uuid,
  p_attachments jsonb,
  p_min int
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_item jsonb;
  v_path text;
  v_mime text;
  v_size bigint;
begin
  if p_attachments is not null and jsonb_typeof(p_attachments) not in ('array', 'null') then
    raise exception 'INVALID_INPUT'
      using detail = 'attachments must be an array', errcode = 'P0001';
  end if;
  v_count := case when p_attachments is null or jsonb_typeof(p_attachments) = 'null'
                  then 0 else jsonb_array_length(p_attachments) end;
  if v_count < p_min then
    raise exception 'EVIDENCE_REQUIRED'
      using detail = format('This status requires at least %s photo(s)', p_min),
            errcode = 'P0001';
  end if;
  if v_count > 3 then
    raise exception 'INVALID_INPUT'
      using detail = 'At most 3 photos per update', errcode = 'P0001';
  end if;
  for v_item in select * from jsonb_array_elements(coalesce(p_attachments, '[]'::jsonb)) loop
    v_path := public._clean_text(v_item->>'objectPath', 512);
    v_mime := public._clean_text(v_item->>'mimeType', 100);
    v_size := coalesce(nullif(v_item->>'sizeBytes', '')::bigint, 0);
    if v_path is null then
      raise exception 'INVALID_INPUT'
        using detail = 'Each attachment needs an objectPath', errcode = 'P0001';
    end if;
    if v_size > 5 * 1024 * 1024 then
      raise exception 'INVALID_INPUT'
        using detail = 'Each photo must be at most 5MB', errcode = 'P0001';
    end if;
    if v_mime is not null and v_mime not in ('image/png', 'image/jpeg', 'image/webp') then
      raise exception 'INVALID_INPUT'
        using detail = 'Evidence must be png/jpeg/webp', errcode = 'P0001';
    end if;
    insert into public.job_attachments
      (job_id, timeline_id, uploaded_by, bucket, object_path, original_name, mime_type, size_bytes)
    values
      (p_job_id, p_timeline_id, p_actor_id, 'job-attachments', v_path,
       public._clean_text(v_item->>'originalName', 255), v_mime, nullif(v_size, 0));
  end loop;
  return v_count;
end $$;

-- ----------------------------------------------------------------------------
-- 2. _create_job_internal — shared normalized creation path (Amendment 1)
--    Callers: create_job (actor = current app user, source 'WebApp') and
--    ingest_google_form_submission (no actor, source 'GoogleForm').
--    The caller can NEVER set: id, status, subStatus, raw, completedAt,
--    verifier/permission/admin fields. PIN is generated and bcrypt-hashed
--    here; plaintext is returned once (WebApp only) and never stored.
-- ----------------------------------------------------------------------------

create or replace function public._create_job_internal(
  p_actor_id uuid,
  p_source text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_room_no text;
  v_room uuid;
  v_assignee uuid;
  v_main text;
  v_job_id text;
  v_prefix text;
  v_pin text;
  v_client_payload jsonb;
  v_job public.jobs%rowtype;
  v_timeline uuid;
  v_attempt int := 0;
begin
  if p_source not in ('WebApp', 'GoogleForm') then
    raise exception 'INVALID_INPUT'
      using detail = 'Unsupported job source', errcode = 'P0001';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'INVALID_INPUT'
      using detail = 'Job payload must be a JSON object', errcode = 'P0001';
  end if;

  v_title := coalesce(public._clean_text(p_payload->>'title', 300),
                      public._clean_text(p_payload->>'issueDescription', 2000));
  if v_title is null then
    raise exception 'INVALID_INPUT'
      using detail = 'title or issueDescription is required', errcode = 'P0001';
  end if;

  v_room_no := coalesce(public._clean_text(p_payload->>'roomNo', 40),
                        public._clean_text(p_payload->>'room', 40));
  if v_room_no is not null then
    select id into v_room from public.rooms where room_no = v_room_no limit 1;
  end if;

  -- Assignment at creation: WebApp + authenticated actor only. The Google
  -- Form boundary can never choose an assignee (Amendment 1).
  v_assignee := null;
  if p_source = 'WebApp' and p_actor_id is not null
     and nullif(p_payload->>'assignee', '') is not null then
    select id into v_assignee from public.app_users
    where id = (p_payload->>'assignee')::uuid
      and is_active and app_role in ('admin', 'coadmin', 'staff');
    if v_assignee is null then
      raise exception 'INVALID_INPUT'
        using detail = 'assignee must be an active staff account', errcode = 'P0001';
    end if;
  end if;

  v_main := coalesce(public._clean_text(p_payload->>'mainCategory', 40), 'resident');

  -- Whitelisted client-display payload. Forbidden/derived keys are dropped;
  -- relational columns stay authoritative via the read merge.
  v_client_payload := jsonb_strip_nulls(jsonb_build_object(
    'title',            v_title,
    'issueDescription', public._clean_text(p_payload->>'issueDescription', 2000),
    'description',      public._clean_text(p_payload->>'issueDescription', 2000),
    'roomNo',           v_room_no,
    'room',             v_room_no,
    'building',         public._clean_text(p_payload->>'building', 60),
    'floor',            public._clean_text(p_payload->>'floor', 20),
    'contactName',      public._clean_text(p_payload->>'contactName', 120),
    'contactPhone',     public._clean_text(p_payload->>'contactPhone', 40),
    'note',             public._clean_text(p_payload->>'note', 2000),
    'slaNote',          public._clean_text(p_payload->>'slaNote', 300),
    'startTime',        public._clean_text(p_payload->>'startTime', 20),
    'endTime',          public._clean_text(p_payload->>'endTime', 20),
    'areaType',         case when v_main = 'common' then 'common' else 'unit' end,
    'idempotencyKey',   public._clean_text(p_payload->>'idempotencyKey', 100)
  ));

  -- Server-generated id: JC- (WebApp) / GF- (GoogleForm), Bangkok date +
  -- random suffix; retry on the (vanishingly rare) collision.
  v_prefix := case when p_source = 'GoogleForm' then 'GF' else 'JC' end;
  loop
    v_job_id := v_prefix || '-'
      || to_char(now() at time zone 'Asia/Bangkok', 'YYMMDD') || '-'
      || upper(encode(gen_random_bytes(3), 'hex'));
    exit when not exists (select 1 from public.jobs where id = v_job_id);
    v_attempt := v_attempt + 1;
    if v_attempt > 5 then
      raise exception 'INVALID_INPUT'
        using detail = 'Could not allocate a job id', errcode = 'P0001';
    end if;
  end loop;

  insert into public.jobs (
    id, source, room_id, reported_by, assigned_by, assignee_id,
    status, sub_status, main_category, category, priority,
    job_date, due_date, next_update_date, share_public, raw, payload
  ) values (
    v_job_id,
    p_source,
    v_room,
    p_actor_id,
    case when v_assignee is not null then p_actor_id else null end,
    v_assignee,
    case when v_assignee is not null then 'received' else 'open' end,
    '',
    v_main,
    coalesce(public._clean_text(p_payload->>'category', 40), 'building'),
    coalesce(public._clean_text(p_payload->>'priority', 20), 'normal'),
    coalesce(public._bkk_date(p_payload->>'jobDate'), public._bkk_today()),
    public._bkk_date(p_payload->>'dueDate'),
    public._bkk_date(p_payload->>'nextUpdateDate'),
    (v_main = 'common') or coalesce((p_payload->>'sharePublic')::boolean, false),
    v_assignee is null,   -- triage flag: untriaged until assigned/classified
    v_client_payload
  )
  returning * into v_job;

  -- Close PIN: generated server-side (pgcrypto randomness), bcrypt-hashed;
  -- plaintext never persisted.
  v_pin := lpad((abs((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::int)::bigint) % 10000)::text, 4, '0');
  insert into public.job_close_pins (job_id, pin_hash)
  values (v_job_id, crypt(v_pin, gen_salt('bf')));

  insert into public.job_timeline (job_id, actor_id, action, from_status, to_status, message, data)
  values (v_job_id, p_actor_id, 'created', null, v_job.status,
          case when p_source = 'GoogleForm' then 'สร้างงานจาก Google Form' else 'สร้างงานผ่านระบบ' end,
          jsonb_build_object('source', p_source))
  returning id into v_timeline;
  if v_assignee is not null then
    insert into public.job_timeline (job_id, actor_id, action, from_status, to_status, message, data)
    values (v_job_id, p_actor_id, 'assigned', 'open', 'received', 'มอบหมายงานเมื่อสร้าง',
            jsonb_build_object('assignee_id', v_assignee));
  end if;

  perform public.append_audit_log(
    case when p_source = 'GoogleForm' then 'GOOGLE_FORM_JOB_CREATED' else 'JOB_CREATED' end,
    v_job_id,
    jsonb_build_object('job_id', v_job_id, 'source', p_source));

  -- closePin is disclosed exactly once, to the authenticated WebApp creator.
  return public._job_read_jsonb(v_job)
    || case when p_source = 'WebApp'
            then jsonb_build_object('closePin', v_pin)
            else '{}'::jsonb end;
end $$;

-- ----------------------------------------------------------------------------
-- 3. create_job — authenticated WebApp intake
-- ----------------------------------------------------------------------------

create or replace function public.create_job(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.current_app_user_id();
  v_key text;
  v_existing public.jobs%rowtype;
begin
  if v_actor is null then
    raise exception 'AUTH_REQUIRED'
      using detail = 'create_job requires an active app account', errcode = 'P0001';
  end if;
  -- Idempotent retry: same creator + same idempotency key returns the
  -- existing job (without the PIN, which is disclosed only on first create).
  v_key := public._clean_text(p_payload->>'idempotencyKey', 100);
  if v_key is not null then
    select * into v_existing from public.jobs
    where reported_by = v_actor and payload->>'idempotencyKey' = v_key
    limit 1;
    if found then
      return public._job_read_jsonb(v_existing)
        || jsonb_build_object('duplicate', true);
    end if;
  end if;
  return public._create_job_internal(v_actor, 'WebApp', p_payload);
end $$;

-- ----------------------------------------------------------------------------
-- 4. assign_job — admin or assignment-capable user; -> received
-- ----------------------------------------------------------------------------

create or replace function public.assign_job(p_job_id text, p_assignee_id uuid, p_extra jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.current_app_user_id();
  v_job public.jobs%rowtype;
  v_main text;
  v_from text;
begin
  if v_actor is null then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
  if not public.can_read_job(p_job_id) then
    raise exception 'JOB_NOT_FOUND' using errcode = 'P0001';
  end if;
  if not (public.is_admin_account()
          or exists (select 1 from public.app_users
                     where id = v_actor and is_active and can_assign
                       and public.can_update_job(p_job_id))) then
    raise exception 'FORBIDDEN'
      using detail = 'Assignment requires admin or assignment permission over this job',
            errcode = '42501';
  end if;
  if not exists (select 1 from public.app_users
                 where id = p_assignee_id and is_active
                   and app_role in ('admin', 'coadmin', 'staff')) then
    raise exception 'INVALID_INPUT'
      using detail = 'assignee must be an active staff account', errcode = 'P0001';
  end if;

  select * into v_job from public.jobs where id = p_job_id for update;
  v_from := v_job.status;
  if not public._is_legal_job_transition(v_job.status, 'received') then
    raise exception 'ILLEGAL_TRANSITION'
      using detail = format('Cannot assign a job in status %s', v_job.status),
            errcode = 'P0001';
  end if;

  v_main := coalesce(public._clean_text(p_extra->>'mainCategory', 40), v_job.main_category);
  update public.jobs set
    assignee_id = p_assignee_id,
    assigned_by = v_actor,
    status = 'received',
    sub_status = '',
    raw = false,                         -- assignment classifies the job
    main_category = v_main,
    category = coalesce(public._clean_text(p_extra->>'category', 40), category),
    share_public = share_public or (v_main = 'common'),
    payload = payload || jsonb_strip_nulls(jsonb_build_object(
      'areaType', case when v_main = 'common' then 'common' else 'unit' end,
      'note',     public._clean_text(p_extra->>'note', 2000))),
    updated_at = now()
  where id = p_job_id
  returning * into v_job;

  insert into public.job_timeline (job_id, actor_id, action, from_status, to_status, message, data)
  values (p_job_id, v_actor, 'assigned', v_from, 'received', 'มอบหมายงาน',
          jsonb_build_object('assignee_id', p_assignee_id));
  perform public.append_audit_log('JOB_ASSIGNED', p_job_id,
    jsonb_build_object('job_id', p_job_id, 'assignee_id', p_assignee_id));

  return public._job_read_jsonb(v_job);
end $$;

-- ----------------------------------------------------------------------------
-- 5. update_job_status — the enforced workflow core (F-04)
-- ----------------------------------------------------------------------------

create or replace function public.update_job_status(p_job_id text, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.current_app_user_id();
  v_job public.jobs%rowtype;
  v_target text;
  v_final_status text;
  v_final_sub text := '';
  v_no_pin boolean := coalesce((p_payload->>'noPinAvailable')::boolean, false);
  v_pin text;
  v_pin_hash text;
  v_reason text;
  v_min_photos int;
  v_timeline uuid;
  v_next_update date;
  v_completed_at timestamptz := null;
  v_from text;
begin
  if v_actor is null then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
  if not public.can_read_job(p_job_id) then
    raise exception 'JOB_NOT_FOUND' using errcode = 'P0001';
  end if;
  if not public.can_update_job(p_job_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  v_target := public._clean_text(p_payload->>'status', 40);
  if v_target is null or v_target not in
     ('received', 'pending_inspection', 'inspected_waiting_repair',
      'repaired_follow_up', 'temporary_waiting_parts', 'completed', 'rejected') then
    raise exception 'INVALID_INPUT'
      using detail = 'Unknown target status', errcode = 'P0001';
  end if;

  select * into v_job from public.jobs where id = p_job_id for update;
  v_from := v_job.status;

  if not public._is_legal_job_transition(v_job.status, v_target) then
    raise exception 'ILLEGAL_TRANSITION'
      using detail = format('%s -> %s is not a legal transition', v_job.status, v_target),
            errcode = 'P0001';
  end if;

  -- Per-status required inputs (mirrors validateStatusUpdate, server-side).
  if v_target = 'pending_inspection' and public._bkk_date(p_payload->>'inspectionDate') is null then
    raise exception 'INVALID_INPUT'
      using detail = 'pending_inspection requires inspectionDate', errcode = 'P0001';
  end if;
  if v_target in ('repaired_follow_up', 'temporary_waiting_parts')
     and public._bkk_date(p_payload->>'nextUpdateDate') is null then
    raise exception 'INVALID_INPUT'
      using detail = 'This status requires nextUpdateDate', errcode = 'P0001';
  end if;
  if v_target = 'inspected_waiting_repair' then
    if public._bkk_date(p_payload->>'updateDate') is null
       or public._clean_text(p_payload->>'cause', 2000) is null
       or public._clean_text(p_payload->>'solution', 2000) is null then
      raise exception 'INVALID_INPUT'
        using detail = 'inspected_waiting_repair requires updateDate, cause and solution',
              errcode = 'P0001';
    end if;
  end if;

  -- Completion gate (F-04): PIN, or forced pending-inspection fallback.
  v_final_status := v_target;
  if v_target = 'completed' then
    if v_no_pin then
      v_reason := public._clean_text(p_payload->>'noPinReason', 1000);
      if v_reason is null then
        raise exception 'INVALID_INPUT'
          using detail = 'noPinAvailable requires noPinReason', errcode = 'P0001';
      end if;
      -- This path NEVER returns completed.
      v_final_status := 'pending_inspection';
      v_final_sub := 'waiting_owner_or_admin_verification';
    else
      v_pin := public._clean_text(p_payload->>'pin', 20);
      select pin_hash into v_pin_hash from public.job_close_pins where job_id = p_job_id;
      if v_pin is null or v_pin_hash is null or crypt(v_pin, v_pin_hash) <> v_pin_hash then
        raise exception 'PIN_INVALID'
          using detail = 'Completion PIN does not match', errcode = 'P0001';
      end if;
      v_completed_at := now();
    end if;
  end if;

  -- nextUpdateDate is only overwritten when the key is present (DB-03).
  v_next_update := case when p_payload ? 'nextUpdateDate'
                        then public._bkk_date(p_payload->>'nextUpdateDate')
                        else v_job.next_update_date end;

  update public.jobs set
    status = v_final_status,
    sub_status = v_final_sub,
    next_update_date = v_next_update,
    completed_at = v_completed_at,
    raw = false,                        -- any staff transition classifies the job
    payload = payload || jsonb_strip_nulls(jsonb_build_object(
      'note',              public._clean_text(p_payload->>'note', 2000),
      'cause',             public._clean_text(p_payload->>'cause', 2000),
      'solution',          public._clean_text(p_payload->>'solution', 2000),
      'inspectionDate',    public._bkk_date(p_payload->>'inspectionDate'),
      'noPinAvailable',    case when v_target = 'completed' then v_no_pin else null end,
      'noPinReason',       v_reason,
      'pendingVerificationAt', case when v_final_sub <> '' then now() end,
      'acceptedAt',        case when v_target = 'received' then now() end,
      'completedWorkDate', case when v_completed_at is not null
                                then coalesce(public._bkk_date(p_payload->>'completedWorkDate'),
                                              public._bkk_today()) end)),
    updated_at = now()
  where id = p_job_id
  returning * into v_job;

  insert into public.job_timeline (job_id, actor_id, action, from_status, to_status, message, data)
  values (p_job_id, v_actor,
          case when v_no_pin and v_target = 'completed' then 'complete_without_pin' else 'status_update' end,
          v_from,
          v_final_status,
          case when v_no_pin and v_target = 'completed'
               then 'ช่างแจ้งเสร็จแต่ไม่มี PIN รอตรวจสอบยืนยัน'
               else 'อัปเดตสถานะงาน' end,
          jsonb_build_object('subStatus', v_final_sub, 'noPinAvailable', v_no_pin))
  returning id into v_timeline;

  -- Evidence: >=1 photo unless the target is received/rejected; max 3; the
  -- no-PIN fallback always requires >=1 photo.
  v_min_photos := case when v_target in ('received', 'rejected') then 0 else 1 end;
  if v_no_pin and v_target = 'completed' then
    v_min_photos := greatest(v_min_photos, 1);
  end if;
  perform public._store_job_evidence(p_job_id, v_timeline, v_actor,
                                     p_payload->'attachments', v_min_photos);

  perform public.append_audit_log('JOB_STATUS_UPDATED', p_job_id,
    jsonb_build_object('job_id', p_job_id, 'from', v_from,
                       'to', v_final_status, 'subStatus', v_final_sub,
                       'noPinAvailable', v_no_pin));

  return public._job_read_jsonb(v_job);
end $$;

-- ----------------------------------------------------------------------------
-- 6. verify_job_completion — restricted verifier set (F-04)
-- ----------------------------------------------------------------------------

create or replace function public.verify_job_completion(p_job_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.current_app_user_id();
  v_job public.jobs%rowtype;
begin
  if v_actor is null then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
  if not public.can_read_job(p_job_id) then
    raise exception 'JOB_NOT_FOUND' using errcode = 'P0001';
  end if;

  select * into v_job from public.jobs where id = p_job_id for update;

  -- Verifiers: admin/co-admin, the assigner, or the reporting room's
  -- resident account — never the mere assignee.
  if not (public.is_admin_account()
          or v_job.assigned_by = v_actor
          or (v_job.room_id is not null and exists (
                select 1 from public.app_users
                where id = v_actor and is_active
                  and app_role = 'resident' and room_id = v_job.room_id))) then
    raise exception 'FORBIDDEN'
      using detail = 'Verification is restricted to admin, assigner or the reporting room',
            errcode = '42501';
  end if;

  if v_job.status <> 'pending_inspection'
     or v_job.sub_status <> 'waiting_owner_or_admin_verification' then
    raise exception 'ILLEGAL_TRANSITION'
      using detail = 'Only a job waiting verification can be verified complete',
            errcode = 'P0001';
  end if;

  update public.jobs set
    status = 'completed',
    sub_status = '',
    completed_at = now(),
    payload = payload || jsonb_build_object(
      'completedWorkDate', coalesce(payload->>'completedWorkDate',
                                    public._bkk_today()::text)),
    updated_at = now()
  where id = p_job_id;

  insert into public.job_timeline (job_id, actor_id, action, from_status, to_status, message, data)
  values (p_job_id, v_actor, 'verified_completed', 'pending_inspection', 'completed',
          'ยืนยันปิดงาน', '{}'::jsonb);
  perform public.append_audit_log('JOB_COMPLETION_VERIFIED', p_job_id,
    jsonb_build_object('job_id', p_job_id));

  return true;
end $$;

-- ----------------------------------------------------------------------------
-- 7. ingest_google_form_submission — single-transaction boundary (Amendment 1)
--    Service-role only (grant unchanged from Stage 1). A plpgsql function IS
--    one transaction: any raised exception rolls back the submission row,
--    the job, the PIN, the timeline and the audit entry together.
-- ----------------------------------------------------------------------------

create or replace function public.ingest_google_form_submission(
  p_external_id text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_external text := public._clean_text(p_external_id, 200);
  v_submission uuid;
  v_existing_job text;
  v_job jsonb;
begin
  if v_external is null then
    raise exception 'INVALID_INPUT'
      using detail = 'external_id is required', errcode = 'P0001';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or p_payload = '{}'::jsonb then
    raise exception 'INVALID_INPUT'
      using detail = 'A non-empty submission payload is required', errcode = 'P0001';
  end if;

  -- Idempotency by external_id: a completed retry returns the existing job.
  select id, job_id into v_submission, v_existing_job
  from public.google_form_submissions
  where external_id = v_external
  for update;
  if found and v_existing_job is not null then
    select public._job_read_jsonb(j) into v_job from public.jobs j where j.id = v_existing_job;
    return jsonb_build_object('job', v_job, 'submission_id', v_submission, 'duplicate', true);
  end if;

  -- The original untrusted payload is preserved verbatim HERE — never on the
  -- job row (jobs.raw is a boolean triage flag).
  if v_submission is null then
    insert into public.google_form_submissions (external_id, status, payload)
    values (v_external, 'new', p_payload)
    returning id into v_submission;
  end if;

  -- Exactly one job, via the shared normalized path. The webhook can never
  -- set actor, assignee, status, completed, verifier or admin fields: only
  -- whitelisted descriptive keys survive _create_job_internal, actor is NULL
  -- and source is fixed. The job enters the triage pool (raw = true).
  v_job := public._create_job_internal(null, 'GoogleForm', p_payload);

  update public.google_form_submissions
  set status = 'processed', job_id = v_job->>'id', processed_at = now()
  where id = v_submission;

  return jsonb_build_object('job', v_job, 'submission_id', v_submission, 'duplicate', false);
end $$;

-- ----------------------------------------------------------------------------
-- 8. get_app_bootstrap — jobs are NEVER served from app_snapshots
--    The snapshot bridge may still carry non-job domains (until Stage 6),
--    but the 'jobs' key is always rebuilt from the relational read path.
-- ----------------------------------------------------------------------------

create or replace function public.get_app_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_snapshot jsonb;
  v_jobs jsonb;
begin
  -- Relational jobs, same shape and filter as list_jobs_for_current_user().
  select coalesce(jsonb_agg(public._job_read_jsonb(j) order by j.created_at desc), '[]'::jsonb)
  into v_jobs
  from public.jobs j
  where public.current_app_user_id() is not null
    and public.can_read_job(j.id);

  if public.is_staff_account() then
    select snapshot into v_snapshot from public.app_snapshots order by created_at desc limit 1;
    if v_snapshot is not null then
      -- Snapshot jobs are stripped and replaced unconditionally.
      return (v_snapshot - 'jobs') || jsonb_build_object('jobs', v_jobs);
    end if;
  end if;

  return jsonb_build_object(
    'jobs', v_jobs,
    'adminLogs', coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from public.audit_logs l where public.is_admin_account()), '[]'::jsonb),
    'staffLogs', coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from public.audit_logs l where public.is_staff_account()), '[]'::jsonb),
    'residentLogs', coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from public.audit_logs l where l.actor_id = public.current_app_user_id()), '[]'::jsonb),
    'residentRooms', '[]'::jsonb,
    'teamOverrides', '{}'::jsonb,
    'customUsers', '[]'::jsonb,
    'deletedUserIds', '[]'::jsonb,
    'announcements', coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.announcements a), '[]'::jsonb),
    'organizationAssignments', '{}'::jsonb
  );
end $$;

comment on function public.get_app_bootstrap() is
  'Stage 2: jobs are always rebuilt from the relational read path; app_snapshots can never serve the jobs key.';

-- ----------------------------------------------------------------------------
-- 9. Grants — helpers are internal-only; public RPC grants are unchanged
--    (CREATE OR REPLACE preserves the Stage 1 ACLs on the public RPCs).
-- ----------------------------------------------------------------------------

revoke all on function public._bkk_date(text) from public, anon, authenticated;
revoke all on function public._bkk_today() from public, anon, authenticated;
revoke all on function public._clean_text(text, int) from public, anon, authenticated;
revoke all on function public._is_legal_job_transition(text, text) from public, anon, authenticated;
revoke all on function public._job_read_jsonb(public.jobs) from public, anon, authenticated;
revoke all on function public._store_job_evidence(text, uuid, uuid, jsonb, int)
  from public, anon, authenticated, service_role;
