-- ============================================================================
-- Juristic Care — Stage 5: import_legacy_job enforced body
-- Plan: docs/audit/14-strategy-b-rebuild-plan.md §4, Amendment 3, and the
-- approved Stage 5 revision (rotate-all PIN, per-record atomicity,
-- deterministic target id, fail-closed embedded evidence).
-- Contract: docs/audit/15-job-domain-rpc-contract.md §8 — the public
-- signature, grants and in-body authorization from Stage 1 are UNCHANGED.
--
-- Boundary rules implemented here:
--   * One RPC call = one record = one transaction. Any write-phase failure
--     rolls back the record's job, PIN, timeline, attachments and audit rows
--     together; the call returns a safe failed result.
--   * p_dry_run = true validates and reports without writing ANY row.
--   * Target id is DETERMINISTIC from normalized source + legacy_id
--     (namespaced sha256, no randomness): re-import order can never change
--     ids, and identical legacy ids under different sources diverge.
--   * PIN policy (Amendment 3, rotate-all): localStorage-origin plaintext is
--     never trusted; a fresh PIN is generated inside the database, stored
--     only as a bcrypt hash with rotated_at, and the plaintext (old or new)
--     is never persisted, returned or logged. Outcomes: pin_rotated | no_pin
--     | pin_migration_failed (pin_migrated is reserved for a future trusted
--     source).
--   * Evidence: only stable managed references (objectPath) map to
--     job_attachments. Embedded dataURL/base64/blob/local-file evidence
--     fails the WHOLE record with EVIDENCE_BINARY_MIGRATION_REQUIRED
--     (binary migration is a future ticket). No Storage upload happens here.
--   * Timeline entries are preserved with imported = true and original
--     created_at; nothing historical is fabricated.
--   * No notification side effects of any kind; audit-only on real success.
-- All pgcrypto calls are schema-qualified (extensions.*).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Internal helpers (EXECUTE revoked from client roles below)
-- ----------------------------------------------------------------------------

-- Deterministic target id: 'LG-' + first 12 hex chars of
-- sha256(lower(trim(source)) || ':' || trim(legacy_id)). Stable across runs
-- and import order; source-namespaced; fits jobs.id (text).
create or replace function public._legacy_job_target_id(p_source text, p_legacy_id text)
returns text
language sql
immutable
set search_path = public
as $$
  select 'LG-' || upper(substr(encode(
           extensions.digest(lower(btrim(p_source)) || ':' || btrim(p_legacy_id), 'sha256'),
           'hex'), 1, 12))
$$;

-- Legacy status aliases (mirrors the frontend legacyStatusMap) + canonical
-- passthrough. Unknown statuses return NULL — the record must fail, never be
-- silently coerced.
create or replace function public._legacy_job_status(p_status text)
returns text
language sql
immutable
set search_path = public
as $$
  select case lower(coalesce(btrim(p_status), ''))
    when 'waiting' then 'open'
    when 'in_progress' then 'received'
    when 'inspecting' then 'pending_inspection'
    when 'waiting_repair' then 'inspected_waiting_repair'
    when 'done' then 'completed'
    when 'follow_up' then 'repaired_follow_up'
    when 'temporary_waiting' then 'temporary_waiting_parts'
    when 'open' then 'open'
    when 'received' then 'received'
    when 'pending_inspection' then 'pending_inspection'
    when 'inspected_waiting_repair' then 'inspected_waiting_repair'
    when 'repaired_follow_up' then 'repaired_follow_up'
    when 'temporary_waiting_parts' then 'temporary_waiting_parts'
    when 'completed' then 'completed'
    when 'rejected' then 'rejected'
    else null
  end
$$;

-- Resolve a legacy person reference: an app_users uuid, or a login_id.
-- Never invents a user: unresolvable returns NULL.
create or replace function public._legacy_resolve_user(p_ref text)
returns uuid
language plpgsql
stable
set search_path = public
as $$
declare
  v uuid;
begin
  if p_ref is null or btrim(p_ref) = '' then return null; end if;
  begin
    v := p_ref::uuid;
    if exists (select 1 from public.app_users where id = v) then return v; end if;
    return null;
  exception when others then
    -- not a uuid; try login_id
    select id into v from public.app_users where login_id = btrim(p_ref) limit 1;
    return v;
  end;
end $$;

-- Parse a legacy timestamp. Naive local timestamps (no zone) are read as
-- Asia/Bangkok; NULL/empty returns NULL; unparseable raises.
create or replace function public._legacy_timestamptz(p_value text)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
begin
  if p_value is null or btrim(p_value) = '' then return null; end if;
  if p_value ~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2})?(\.\d+)?$' then
    return (p_value::timestamp) at time zone 'Asia/Bangkok';
  end if;
  return p_value::timestamptz;
end $$;

-- Classify one attachment entry.
--   'stable'  : object with a safe managed objectPath (no embedded data)
--   'binary'  : dataURL/base64/blob/local-file → record must fail
--   'invalid' : anything else unusable
create or replace function public._legacy_evidence_kind(p_item jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_path text;
begin
  if p_item is null then return 'invalid'; end if;
  if jsonb_typeof(p_item) = 'string' then
    return 'binary'; -- bare strings in legacy data are dataURL previews
  end if;
  if jsonb_typeof(p_item) <> 'object' then return 'invalid'; end if;
  -- any embedded payload marker anywhere in the object → binary
  if coalesce(p_item->>'dataUrl', p_item->>'src', p_item->>'previewUrl', '') like 'data:%'
     or coalesce(p_item->>'objectPath', p_item->>'path', '') like 'data:%'
     or p_item ? 'blob' or p_item ? 'file' then
    return 'binary';
  end if;
  v_path := coalesce(p_item->>'objectPath', p_item->>'path', '');
  if v_path = '' then
    -- an attachment object with no managed reference is unrecoverable
    return 'binary';
  end if;
  if v_path ~ '^[A-Za-z0-9][A-Za-z0-9/_\.\-]{2,510}$' then
    return 'stable';
  end if;
  return 'invalid';
end $$;

-- ----------------------------------------------------------------------------
-- 2. import_legacy_job — enforced body (signature & grants unchanged)
-- ----------------------------------------------------------------------------

create or replace function public.import_legacy_job(
  p_import_batch_id uuid,
  p_job jsonb,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_legacy_id text;
  v_source text;
  v_status text;
  v_sub text;
  v_target_id text;
  v_created timestamptz;
  v_updated timestamptz;
  v_completed timestamptz;
  v_room uuid;
  v_reporter uuid;
  v_assignee uuid;
  v_assigned_by uuid;
  v_pin_outcome text;
  v_new_pin text;
  v_notes text[] := '{}';
  v_item jsonb;
  v_kind text;
  v_stable_refs jsonb := '[]'::jsonb;
  v_tl jsonb;
  v_tl_at timestamptz;
  v_payload jsonb;
begin
  -- Contract authorization (unchanged from Stage 1): admin app accounts or
  -- the service role only. Anonymous / ordinary users are rejected here.
  if not (public.is_admin_account() or coalesce(auth.role(), '') = 'service_role') then
    raise exception 'FORBIDDEN'
      using detail = 'import_legacy_job is restricted to admin or service-role callers.',
            errcode = '42501';
  end if;

  if p_import_batch_id is null then
    return jsonb_build_object('legacy_id', null, 'status', 'failed',
      'reason', 'MISSING_IMPORT_BATCH_ID', 'pin_outcome', 'no_pin');
  end if;
  if p_job is null or jsonb_typeof(p_job) <> 'object' then
    return jsonb_build_object('legacy_id', null, 'status', 'failed',
      'reason', 'INVALID_RECORD', 'pin_outcome', 'no_pin');
  end if;

  v_legacy_id := public._clean_text(coalesce(p_job->>'legacyId', p_job->>'id'), 100);
  if v_legacy_id is null then
    return jsonb_build_object('legacy_id', null, 'status', 'failed',
      'reason', 'MISSING_LEGACY_ID', 'pin_outcome', 'no_pin');
  end if;

  -- Source is preserved verbatim in its dedicated column (default provenance
  -- tag per plan §4). Never 'WebApp'/'GoogleForm' — those are live sources.
  v_source := coalesce(public._clean_text(p_job->>'source', 60), 'legacy_local_storage');
  if v_source in ('WebApp', 'GoogleForm') then
    v_source := 'legacy_local_storage';
  end if;

  -- Delete-request tickets and other pseudo-jobs are not maintenance jobs.
  if v_legacy_id like 'DEL-%' or p_job ? 'deleteRequest' then
    return jsonb_build_object('legacy_id', v_legacy_id, 'status', 'skipped',
      'reason', 'pseudo_job', 'pin_outcome', 'no_pin');
  end if;

  -- Idempotency: an existing (source, legacy_id) is skipped, never mutated.
  if exists (select 1 from public.jobs
             where source = v_source and legacy_id = v_legacy_id) then
    return jsonb_build_object('legacy_id', v_legacy_id, 'status', 'skipped',
      'reason', 'already_imported', 'pin_outcome', 'no_pin');
  end if;

  -- Status / sub-status: approved mappings only; unknown values fail.
  v_status := public._legacy_job_status(p_job->>'status');
  if v_status is null then
    return jsonb_build_object('legacy_id', v_legacy_id, 'status', 'failed',
      'reason', 'INVALID_STATUS', 'pin_outcome', 'no_pin');
  end if;
  v_sub := coalesce(public._clean_text(p_job->>'subStatus', 60), '');
  if v_sub not in ('', 'waiting_owner_or_admin_verification')
     or (v_sub = 'waiting_owner_or_admin_verification' and v_status <> 'pending_inspection') then
    return jsonb_build_object('legacy_id', v_legacy_id, 'status', 'failed',
      'reason', 'INVALID_SUB_STATUS', 'pin_outcome', 'no_pin');
  end if;

  -- Timestamps preserved verbatim; impossible combinations fail.
  begin
    v_created := coalesce(public._legacy_timestamptz(p_job->>'createdAt'),
                          public._legacy_timestamptz(
                            nullif(concat(p_job->>'date', 'T', coalesce(nullif(p_job->>'time',''),'00:00')), 'T00:00')));
    v_updated := coalesce(public._legacy_timestamptz(p_job->>'updatedAt'), v_created);
    v_completed := public._legacy_timestamptz(p_job->>'completedAt');
  exception when others then
    return jsonb_build_object('legacy_id', v_legacy_id, 'status', 'failed',
      'reason', 'INVALID_TIMESTAMP', 'pin_outcome', 'no_pin');
  end;
  if v_created is null then
    return jsonb_build_object('legacy_id', v_legacy_id, 'status', 'failed',
      'reason', 'MISSING_CREATED_AT', 'pin_outcome', 'no_pin');
  end if;
  if v_updated < v_created or (v_completed is not null and v_completed < v_created) then
    return jsonb_build_object('legacy_id', v_legacy_id, 'status', 'failed',
      'reason', 'INVALID_TIMESTAMP_ORDER', 'pin_outcome', 'no_pin');
  end if;
  if v_status = 'completed' and v_completed is null then
    v_completed := v_updated;
    v_notes := v_notes || 'completed_at_defaulted_to_updated_at';
  end if;
  if v_status <> 'completed' then
    v_completed := null;
  end if;

  -- Evidence classification BEFORE any write decision: one embedded binary
  -- item fails the whole record (fail-closed; future binary-migration ticket).
  for v_item in select * from jsonb_array_elements(coalesce(
      case when jsonb_typeof(p_job->'attachments') = 'array' then p_job->'attachments' end,
      '[]'::jsonb)) loop
    v_kind := public._legacy_evidence_kind(v_item);
    if v_kind = 'binary' then
      return jsonb_build_object('legacy_id', v_legacy_id, 'status', 'failed',
        'reason', 'EVIDENCE_BINARY_MIGRATION_REQUIRED', 'pin_outcome', 'no_pin');
    elsif v_kind = 'invalid' then
      return jsonb_build_object('legacy_id', v_legacy_id, 'status', 'failed',
        'reason', 'EVIDENCE_UNRECOGNIZED', 'pin_outcome', 'no_pin');
    else
      v_stable_refs := v_stable_refs || jsonb_build_array(v_item);
    end if;
  end loop;

  -- Relationships: resolve or record NULL + note. Never invent a user/room.
  v_reporter := public._legacy_resolve_user(coalesce(p_job->>'reporter', p_job->>'createdBy'));
  if coalesce(p_job->>'reporter', p_job->>'createdBy') is not null and v_reporter is null then
    v_notes := v_notes || 'unresolved_reporter';
  end if;
  v_assignee := public._legacy_resolve_user(p_job->>'assignee');
  if nullif(p_job->>'assignee', '') is not null and v_assignee is null then
    v_notes := v_notes || 'unresolved_assignee';
  end if;
  v_assigned_by := public._legacy_resolve_user(p_job->>'assignedBy');
  if nullif(p_job->>'assignedBy', '') is not null and v_assigned_by is null then
    v_notes := v_notes || 'unresolved_assigned_by';
  end if;
  select id into v_room from public.rooms
  where room_no = coalesce(public._clean_text(p_job->>'roomNo', 40),
                           public._clean_text(p_job->>'room', 40))
  limit 1;
  if v_room is null then
    v_notes := v_notes || 'unresolved_room';
  end if;

  -- PIN plan (rotate-all): plaintext from client storage is never trusted or
  -- preserved. Active jobs get a fresh in-DB PIN (hash only); terminal jobs
  -- or absent PINs get none. The plaintext (old or new) never leaves the DB.
  if nullif(p_job->>'closePin', '') is not null
     and v_status not in ('completed', 'rejected') then
    v_pin_outcome := 'pin_rotated';
  else
    v_pin_outcome := 'no_pin';
  end if;

  v_target_id := public._legacy_job_target_id(v_source, v_legacy_id);

  if p_dry_run then
    -- Dry-run writes NOTHING: no jobs, pins, timeline, attachments, audit.
    return jsonb_build_object(
      'legacy_id', v_legacy_id, 'status', 'ok',
      'reason', case when array_length(v_notes, 1) is null then 'dry_run_valid'
                     else 'dry_run_valid: ' || array_to_string(v_notes, ',') end,
      'pin_outcome', v_pin_outcome, 'dry_run', true, 'target_id', v_target_id);
  end if;

  -- ---- WRITE PHASE: one nested block = per-record rollback boundary -------
  begin
    -- Display payload whitelist (PIN-like keys are never copied).
    v_payload := jsonb_strip_nulls(jsonb_build_object(
      'title',            p_job->'title',
      'description',      p_job->'description',
      'issueDescription', p_job->'issueDescription',
      'room',             p_job->'room',
      'roomNo',           p_job->'roomNo',
      'areaType',         p_job->'areaType',
      'note',             p_job->'note',
      'slaNote',          p_job->'slaNote',
      'startTime',        p_job->'startTime',
      'endTime',          p_job->'endTime',
      'assigneeName',     p_job->'assigneeName',
      'assignedByName',   p_job->'assignedByName',
      'noPinAvailable',   p_job->'noPinAvailable',
      'noPinReason',      p_job->'noPinReason',
      'legacyNotes',      case when array_length(v_notes, 1) is not null
                               then to_jsonb(v_notes) end));

    if exists (select 1 from public.jobs where id = v_target_id) then
      raise exception 'TARGET_ID_COLLISION';
    end if;

    insert into public.jobs (
      id, source, legacy_id, import_batch_id, raw,
      room_id, reported_by, assigned_by, assignee_id,
      status, sub_status, main_category, category, priority,
      job_date, due_date, next_update_date, share_public,
      completed_at, payload, created_at, updated_at
    ) values (
      v_target_id, v_source, v_legacy_id, p_import_batch_id,
      coalesce((p_job->>'raw')::boolean, false),
      v_room, v_reporter, v_assigned_by, v_assignee,
      v_status, v_sub,
      coalesce(public._clean_text(p_job->>'mainCategory', 40), 'resident'),
      coalesce(public._clean_text(p_job->>'category', 40), 'building'),
      coalesce(public._clean_text(p_job->>'priority', 20), 'normal'),
      public._bkk_date(coalesce(p_job->>'jobDate', p_job->>'date')),
      public._bkk_date(p_job->>'dueDate'),
      public._bkk_date(p_job->>'nextUpdateDate'),
      coalesce((p_job->>'sharePublic')::boolean, false),
      v_completed, v_payload, v_created, v_updated
    );

    if v_pin_outcome = 'pin_rotated' then
      begin
        v_new_pin := lpad((abs(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::int))::bigint) % 10000)::text, 4, '0');
        insert into public.job_close_pins (job_id, pin_hash, rotated_at)
        values (v_target_id, extensions.crypt(v_new_pin, extensions.gen_salt('bf')), now());
        v_new_pin := null; -- plaintext discarded; never returned or logged
      exception when others then
        raise exception 'PIN_MIGRATION_FAILED';
      end;
    end if;

    -- Timeline: preserve source entries with imported provenance; nothing is
    -- fabricated for records that had no history.
    for v_tl in select * from jsonb_array_elements(coalesce(
        case when jsonb_typeof(p_job->'timeline') = 'array' then p_job->'timeline' end,
        '[]'::jsonb)) loop
      v_tl_at := coalesce(public._legacy_timestamptz(v_tl->>'at'), v_created);
      insert into public.job_timeline
        (job_id, actor_id, action, from_status, to_status, message, data, created_at, imported)
      values (
        v_target_id,
        public._legacy_resolve_user(v_tl->>'by'),
        coalesce(public._clean_text(v_tl->>'action', 60), 'update'),
        public._clean_text(v_tl->>'fromStatus', 60),
        public._clean_text(v_tl->>'toStatus', 60),
        public._clean_text(v_tl->>'message', 2000),
        (coalesce(v_tl->'data', '{}'::jsonb)) - 'pin' - 'closePin' - 'pinHash',
        v_tl_at, true);
    end loop;

    -- Stable managed evidence references only (classification already done).
    for v_item in select * from jsonb_array_elements(v_stable_refs) loop
      insert into public.job_attachments
        (job_id, uploaded_by, bucket, object_path, original_name, mime_type, size_bytes, created_at)
      values (
        v_target_id, null,
        coalesce(public._clean_text(v_item->>'bucket', 60), 'job-attachments'),
        coalesce(v_item->>'objectPath', v_item->>'path'),
        public._clean_text(v_item->>'originalName', 255),
        public._clean_text(v_item->>'mimeType', 100),
        nullif(coalesce(nullif(v_item->>'sizeBytes', ''), '0')::bigint, 0),
        v_created);
    end loop;

    -- Audit-only side effect (no notifications of any kind).
    perform public.append_audit_log('LEGACY_JOB_IMPORTED', v_legacy_id,
      jsonb_build_object('job_id', v_target_id, 'legacy_id', v_legacy_id,
                         'import_batch_id', p_import_batch_id,
                         'pin_outcome', v_pin_outcome));
  exception when others then
    -- Per-record rollback: the nested block discards every write above.
    return jsonb_build_object('legacy_id', v_legacy_id, 'status', 'failed',
      'reason', case
        when sqlerrm like '%PIN_MIGRATION_FAILED%' then 'PIN_MIGRATION_FAILED'
        when sqlerrm like '%TARGET_ID_COLLISION%' then 'TARGET_ID_COLLISION'
        when sqlerrm like '%uq_jobs_source_legacy%' then 'already_imported_concurrent'
        else 'WRITE_FAILED: ' || left(sqlerrm, 120) end,
      'pin_outcome', case when sqlerrm like '%PIN_MIGRATION_FAILED%'
                          then 'pin_migration_failed' else 'no_pin' end);
  end;

  return jsonb_build_object(
    'legacy_id', v_legacy_id, 'status', 'ok',
    'reason', case when array_length(v_notes, 1) is null then 'imported'
                   else 'imported: ' || array_to_string(v_notes, ',') end,
    'pin_outcome', v_pin_outcome, 'target_id', v_target_id);
end $$;

comment on function public.import_legacy_job(uuid, jsonb, boolean) is
  'Stage 5 legacy import: admin/service-role only; per-record transaction; dry-run writes nothing; deterministic LG- target id from source+legacy_id; rotate-all PIN policy (hash only, plaintext never returned); embedded binary evidence fails closed (EVIDENCE_BINARY_MIGRATION_REQUIRED); timeline imported with provenance; audit-only side effects.';

-- ----------------------------------------------------------------------------
-- 3. Helper grants — internal only
-- ----------------------------------------------------------------------------

revoke all on function public._legacy_job_target_id(text, text) from public, anon, authenticated;
revoke all on function public._legacy_job_status(text) from public, anon, authenticated;
revoke all on function public._legacy_resolve_user(text) from public, anon, authenticated;
revoke all on function public._legacy_timestamptz(text) from public, anon, authenticated;
revoke all on function public._legacy_evidence_kind(jsonb) from public, anon, authenticated;
