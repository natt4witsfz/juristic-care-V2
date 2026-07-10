-- ============================================================================
-- Stage 2 smoke test — structural + behavioral assertions for
-- supabase/migrations/202607100003_job_domain_stage2.sql
--
-- Run against a STAGING database with migrations 202607090001, 202607100001,
-- 202607100002 (pgcrypto forward fix), 202607100003 and 202607100004
-- (_clean_text chr(0) forward fix) applied
-- (Supabase SQL Editor, or psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f ...).
-- Plain SQL only — no psql meta-commands.
--
-- Sections 1–5b are read-only DO-block assertions. Section 6 is a write
-- round-trip wrapped in BEGIN/ROLLBACK, so nothing persists.
--
-- Status: 202607100003 is applied to staging; linked db lint then flagged
-- _clean_text ("null character not permitted" from chr(0)), fixed forward by
-- 202607100004 (not yet applied). This smoke test has not yet been executed
-- against PostgreSQL.
--
-- NOTE: stage1_smoke.sql section 6 asserted the Stage 1 fail-closed stubs
-- (JOB_WRITES_UNAVAILABLE / INGESTION_UNAVAILABLE). Once Stage 2 is applied
-- those stubs no longer exist BY DESIGN; this file supersedes that section.
-- ============================================================================

-- 1. Workflow functions exist, SECURITY DEFINER where required ---------------
do $$
declare
  f record;
begin
  for f in
    select * from (values
      ('create_job'), ('assign_job'), ('update_job_status'),
      ('verify_job_completion'), ('_create_job_internal'),
      ('ingest_google_form_submission'), ('get_app_bootstrap'),
      ('_store_job_evidence')
    ) as v(fname)
  loop
    if not exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f.fname
        and p.prosecdef
        and exists (select 1 from unnest(coalesce(p.proconfig, '{}'))
                    as cfg where cfg like 'search_path=%')
    ) then
      raise exception 'FAIL: % missing, not SECURITY DEFINER, or search_path not fixed', f.fname;
    end if;
  end loop;
  for f in
    select * from (values
      ('_bkk_date'), ('_bkk_today'), ('_clean_text'),
      ('_is_legal_job_transition'), ('_job_read_jsonb')
    ) as v(fname)
  loop
    if not exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f.fname
    ) then
      raise exception 'FAIL: helper % missing', f.fname;
    end if;
  end loop;
  raise notice 'PASS: Stage 2 functions and helpers exist';
end $$;

-- 2. Stage 1 stubs are gone; enforcement markers are present ------------------
do $$
declare
  src text;
begin
  for src in
    select p.prosrc from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('create_job','assign_job','update_job_status',
                        'verify_job_completion','ingest_google_form_submission')
  loop
    if src like '%JOB_WRITES_UNAVAILABLE%' or src like '%INGESTION_UNAVAILABLE%' then
      raise exception 'FAIL: a Stage 1 fail-closed stub body is still installed';
    end if;
  end loop;

  select p.prosrc into src from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'update_job_status';
  if src not like '%PIN_INVALID%' then
    raise exception 'FAIL: update_job_status has no PIN enforcement';
  end if;
  if src not like '%waiting_owner_or_admin_verification%' then
    raise exception 'FAIL: update_job_status has no no-PIN pending-inspection fallback';
  end if;
  if src not like '%_is_legal_job_transition%' then
    raise exception 'FAIL: update_job_status does not consult the transition table';
  end if;
  if src not like '%_store_job_evidence%' then
    raise exception 'FAIL: update_job_status does not enforce evidence';
  end if;

  select p.prosrc into src from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'verify_job_completion';
  if src not like '%pending_inspection%' or src not like '%waiting_owner_or_admin_verification%' then
    raise exception 'FAIL: verify_job_completion does not gate on the verification sub-status';
  end if;
  raise notice 'PASS: enforced bodies installed (PIN, fallback, transitions, evidence)';
end $$;

-- 3. get_app_bootstrap never serves jobs from app_snapshots -------------------
do $$
declare
  src text;
begin
  select p.prosrc into src from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_app_bootstrap';
  if src is null then
    raise exception 'FAIL: get_app_bootstrap missing';
  end if;
  -- The snapshot, when used at all, must have its jobs key stripped and
  -- replaced with the relational job list.
  if src not like '%- ''jobs''%' then
    raise exception 'FAIL: get_app_bootstrap does not strip the snapshot jobs key';
  end if;
  if src like '%return v_snapshot;%' then
    raise exception 'FAIL: get_app_bootstrap can still return a raw snapshot verbatim';
  end if;
  if src not like '%can_read_job%' then
    raise exception 'FAIL: get_app_bootstrap does not build jobs from the relational read path';
  end if;
  raise notice 'PASS: get_app_bootstrap always rebuilds jobs relationally';
end $$;

-- 4. Transition table: legal and illegal moves --------------------------------
do $$
begin
  if not public._is_legal_job_transition('open', 'received') then
    raise exception 'FAIL: open -> received must be legal';
  end if;
  if not public._is_legal_job_transition('received', 'pending_inspection') then
    raise exception 'FAIL: received -> pending_inspection must be legal';
  end if;
  if not public._is_legal_job_transition('received', 'completed') then
    raise exception 'FAIL: received -> completed must be legal (PIN-gated)';
  end if;
  if public._is_legal_job_transition('completed', 'received') then
    raise exception 'FAIL: completed is terminal';
  end if;
  if public._is_legal_job_transition('rejected', 'received') then
    raise exception 'FAIL: rejected is terminal';
  end if;
  if public._is_legal_job_transition('received', 'open') then
    raise exception 'FAIL: no transition may return to open';
  end if;
  if public._is_legal_job_transition('open', 'completed') then
    raise exception 'FAIL: open -> completed must be illegal';
  end if;
  raise notice 'PASS: legal-transition table behaves as specified';
end $$;

-- 5. Asia/Bangkok date normalization (no UTC off-by-one) ----------------------
do $$
begin
  -- 2026-07-09 17:30 UTC is 2026-07-10 00:30 in Bangkok.
  if public._bkk_date('2026-07-09T17:30:00Z') <> date '2026-07-10' then
    raise exception 'FAIL: near-midnight UTC timestamp maps to the wrong Bangkok date';
  end if;
  if public._bkk_date('2026-07-10') <> date '2026-07-10' then
    raise exception 'FAIL: plain date passes through unchanged';
  end if;
  if public._bkk_date('') is not null or public._bkk_date(null) is not null then
    raise exception 'FAIL: empty date must normalize to NULL';
  end if;
  raise notice 'PASS: Asia/Bangkok date normalization';
end $$;

-- 5b. _clean_text sanitization (forward fix 202607100004) ---------------------
do $$
declare
  src text;
begin
  if public._clean_text('  example  ', 20) is distinct from 'example' then
    raise exception 'FAIL: _clean_text does not trim to ''example''';
  end if;
  if public._clean_text('   ', 20) is not null then
    raise exception 'FAIL: _clean_text of whitespace-only must be NULL';
  end if;
  if public._clean_text(null, 20) is not null then
    raise exception 'FAIL: _clean_text of NULL must be NULL';
  end if;
  begin
    perform public._clean_text(repeat('x', 21), 20);
    raise exception 'FAIL: _clean_text accepted an over-length value';
  exception when others then
    if sqlerrm not like '%INVALID_INPUT%' then
      raise exception 'FAIL: over-length value raised unexpected error: %', sqlerrm;
    end if;
  end;
  select p.prosrc into src from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = '_clean_text';
  if src is null then
    raise exception 'FAIL: _clean_text missing';
  end if;
  if src like '%chr(0)%' then
    raise exception 'FAIL: _clean_text still constructs chr(0) (null character not permitted)';
  end if;
  if src like '%replace(p_value%' then
    raise exception 'FAIL: _clean_text still contains a null-character replacement';
  end if;
  raise notice 'PASS: _clean_text trims, nulls empties, caps length, no chr(0)';
end $$;

-- 6. Transactional write round-trip (ROLLED BACK — persists nothing) ----------
begin;

do $$
declare
  v1 jsonb;
  v2 jsonb;
  v_job_id text;
begin
  -- Invalid inputs fail closed.
  begin
    perform public.ingest_google_form_submission(null, '{"title":"x"}'::jsonb);
    raise exception 'FAIL: ingestion accepted a null external_id';
  exception when others then
    if sqlerrm not like '%INVALID_INPUT%' then
      raise exception 'FAIL: unexpected error for null external_id: %', sqlerrm;
    end if;
  end;
  begin
    perform public.ingest_google_form_submission('smoke-2-a', '{}'::jsonb);
    raise exception 'FAIL: ingestion accepted an empty payload';
  exception when others then
    if sqlerrm not like '%INVALID_INPUT%' then
      raise exception 'FAIL: unexpected error for empty payload: %', sqlerrm;
    end if;
  end;

  -- One valid submission creates exactly one raw=true open GF- job.
  v1 := public.ingest_google_form_submission('smoke-2-b',
          '{"title":"Smoke test leak","roomNo":"9999","contactName":"Smoke","status":"completed","assignee":"ignored"}'::jsonb);
  v_job_id := v1->'job'->>'id';
  if v_job_id is null or v_job_id not like 'GF-%' then
    raise exception 'FAIL: ingestion did not produce a GF- job id (%)', v_job_id;
  end if;
  if (v1->>'duplicate')::boolean then
    raise exception 'FAIL: first ingestion reported duplicate';
  end if;
  if not exists (select 1 from public.jobs
                 where id = v_job_id and raw = true and status = 'open'
                   and source = 'GoogleForm' and assignee_id is null
                   and completed_at is null) then
    raise exception 'FAIL: ingested job is not an untriaged open GoogleForm job (forbidden fields must be ignored)';
  end if;
  if v1->'job' ? 'closePin' then
    raise exception 'FAIL: ingestion result leaked a close PIN';
  end if;
  if not exists (select 1 from public.google_form_submissions
                 where external_id = 'smoke-2-b' and job_id = v_job_id
                   and status = 'processed') then
    raise exception 'FAIL: submission row missing or not linked';
  end if;
  if not exists (select 1 from public.job_close_pins where job_id = v_job_id
                   and pin_hash like '$2%') then
    raise exception 'FAIL: bcrypt close PIN row missing';
  end if;
  if not exists (select 1 from public.job_timeline
                 where job_id = v_job_id and action = 'created') then
    raise exception 'FAIL: initial timeline event missing';
  end if;
  if not exists (select 1 from public.audit_logs
                 where action = 'GOOGLE_FORM_JOB_CREATED'
                   and payload->>'job_id' = v_job_id) then
    raise exception 'FAIL: audit log entry missing';
  end if;

  -- Idempotent retry returns the SAME job, creates nothing new.
  v2 := public.ingest_google_form_submission('smoke-2-b', '{"title":"retry"}'::jsonb);
  if not (v2->>'duplicate')::boolean or (v2->'job'->>'id') <> v_job_id then
    raise exception 'FAIL: duplicate external_id did not return the existing job';
  end if;
  if (select count(*) from public.jobs where source = 'GoogleForm'
        and payload->>'title' in ('Smoke test leak', 'retry')) <> 1 then
    raise exception 'FAIL: duplicate external_id created a second job';
  end if;

  raise notice 'PASS: transactional ingestion (idempotent, exactly one job + pin + timeline + audit)';
end $$;

rollback;

do $$ begin raise notice 'STAGE 2 SMOKE: ALL ASSERTIONS PASSED (write section rolled back)'; end $$;
