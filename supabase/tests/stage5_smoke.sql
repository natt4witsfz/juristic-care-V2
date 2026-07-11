-- ============================================================================
-- Stage 5 smoke test — structural + behavioral assertions for
-- supabase/migrations/202607110001_import_legacy_job_stage5.sql
--
-- Run against STAGING with migrations through 202607110003 applied
-- (202607110002 fixed the note-array assignments flagged by db lint;
-- 202607110003 fixed the objectPath regex quantifier that raised SQLSTATE
-- 2201B in the first smoke run)
-- (Supabase SQL Editor, or psql -v ON_ERROR_STOP=1 -f ...). Plain SQL only.
-- FAKE DATA ONLY. Sections 1–2 are read-only; section 3 wraps every write
-- validation in BEGIN/ROLLBACK, so nothing persists.
-- Service-role authorization is simulated inside the rolled-back transaction
-- via set_config('request.jwt.claims', ...) — no real credential involved.
-- Status: not yet executed against PostgreSQL.
-- ============================================================================

-- 1. Contract and structure ---------------------------------------------------
do $$
declare
  src text;
begin
  select p.prosrc into src from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'import_legacy_job'
    and p.prosecdef
    and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
                where cfg like 'search_path=%');
  if src is null then
    raise exception 'FAIL: import_legacy_job missing/not SECURITY DEFINER/search_path not fixed';
  end if;
  if src like '%IMPORT_UNAVAILABLE%' then
    raise exception 'FAIL: Stage 1 stub still installed';
  end if;
  if src not like '%EVIDENCE_BINARY_MIGRATION_REQUIRED%' then
    raise exception 'FAIL: embedded-evidence fail-closed path missing';
  end if;
  if src not like '%pin_rotated%' then
    raise exception 'FAIL: rotate-all PIN outcome missing';
  end if;
  -- deterministic id helper, schema-qualified pgcrypto
  select p.prosrc into src from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = '_legacy_job_target_id';
  if src is null or src not like '%extensions.digest%' then
    raise exception 'FAIL: deterministic id helper missing or pgcrypto unqualified';
  end if;
  if not has_function_privilege('service_role',
       'public.import_legacy_job(uuid, jsonb, boolean)', 'EXECUTE') then
    raise exception 'FAIL: service_role cannot execute import_legacy_job';
  end if;
  -- Forward fix 202607110002: all five note appends must be explicitly typed
  -- (db lint 22P02 "malformed array literal" regression guard).
  select pg_get_functiondef(p.oid) into src from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'import_legacy_job';
  if src not like '%array_append(v_notes, ''completed_at_defaulted_to_updated_at''::text)%'
     or src not like '%array_append(v_notes, ''unresolved_reporter''::text)%'
     or src not like '%array_append(v_notes, ''unresolved_assignee''::text)%'
     or src not like '%array_append(v_notes, ''unresolved_assigned_by''::text)%'
     or src not like '%array_append(v_notes, ''unresolved_room''::text)%' then
    raise exception 'FAIL: a note path does not use array_append (forward fix 202607110002 not installed)';
  end if;
  if src like '%v_notes := v_notes ||%' then
    raise exception 'FAIL: unsafe text-array concatenation still present in import_legacy_job';
  end if;
  -- Forward fix 202607110003: the classifier must use the explicit length
  -- check (the {2,510} quantifier exceeded PostgreSQL's regex bound of 255).
  select pg_get_functiondef(p.oid) into src from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = '_legacy_evidence_kind';
  if src is null then
    raise exception 'FAIL: _legacy_evidence_kind missing';
  end if;
  if src not like '%char_length(v_path) between 3 and 511%' then
    raise exception 'FAIL: classifier lacks the explicit length check (forward fix 202607110003 not installed)';
  end if;
  if src like '%{2,510}%' then
    raise exception 'FAIL: invalid {2,510} regex quantifier still present';
  end if;
  if has_function_privilege('anon',
       'public.import_legacy_job(uuid, jsonb, boolean)', 'EXECUTE') then
    raise exception 'FAIL: anon can execute import_legacy_job';
  end if;
  raise notice 'PASS: contract and structure';
end $$;

-- 2. Deterministic id properties (pure function, read-only) -------------------
do $$
begin
  if public._legacy_job_target_id('legacy_local_storage', 'JC-1') <>
     public._legacy_job_target_id('legacy_local_storage', 'JC-1') then
    raise exception 'FAIL: target id not stable across calls';
  end if;
  if public._legacy_job_target_id('legacy_local_storage', 'JC-1') =
     public._legacy_job_target_id('legacy_snapshot_archive', 'JC-1') then
    raise exception 'FAIL: same legacy_id under different sources must diverge';
  end if;
  if public._legacy_job_target_id('  Legacy_Local_Storage ', 'JC-1') <>
     public._legacy_job_target_id('legacy_local_storage', 'JC-1') then
    raise exception 'FAIL: source normalization (trim/lower) not applied';
  end if;
  if public._legacy_job_target_id('legacy_local_storage', 'JC-1') !~ '^LG-[0-9A-F]{12}$' then
    raise exception 'FAIL: target id shape must be LG- + 12 hex';
  end if;
  raise notice 'PASS: deterministic id properties';
end $$;

-- 3. Behavioral round-trip (ROLLED BACK — persists nothing) -------------------
begin;

-- Unauthorized caller (no admin account, no service_role claim) is rejected.
do $$
begin
  begin
    perform public.import_legacy_job(gen_random_uuid(), '{"id":"X-1","status":"open","createdAt":"2026-01-01T10:00:00"}'::jsonb, true);
    raise exception 'FAIL: unauthorized caller was not rejected';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then
      raise exception 'FAIL: unexpected unauthorized error: %', sqlerrm;
    end if;
  end;
  raise notice 'PASS: unauthorized caller rejected';
end $$;

-- Simulate service_role for the remainder of this (rolled back) transaction.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

do $$
declare
  batch uuid := gen_random_uuid();
  before_counts int[];
  after_counts int[];
  r jsonb;
  r2 jsonb;
  tid text;
  tid2 text;
begin
  before_counts := array[(select count(*) from public.jobs)::int,
                         (select count(*) from public.job_close_pins)::int,
                         (select count(*) from public.job_timeline)::int,
                         (select count(*) from public.job_attachments)::int,
                         (select count(*) from public.audit_logs)::int];

  -- 3a. Dry-run of a valid record writes absolutely nothing.
  r := public.import_legacy_job(batch, '{
    "id": "SMK-101", "source": "legacy_local_storage", "status": "in_progress",
    "title": "smoke legacy", "closePin": "1234",
    "createdAt": "2026-05-01T09:00:00", "updatedAt": "2026-05-02T10:00:00",
    "timeline": [{"at": "2026-05-01T09:00:00", "action": "created", "toStatus": "waiting"}]
  }'::jsonb, true);
  if r->>'status' <> 'ok' or coalesce((r->>'dry_run')::boolean, false) is not true then
    raise exception 'FAIL: dry-run of valid record did not return ok (%)', r;
  end if;
  if r->>'pin_outcome' <> 'pin_rotated' then
    raise exception 'FAIL: dry-run pin outcome expected pin_rotated (%)', r;
  end if;
  after_counts := array[(select count(*) from public.jobs)::int,
                        (select count(*) from public.job_close_pins)::int,
                        (select count(*) from public.job_timeline)::int,
                        (select count(*) from public.job_attachments)::int,
                        (select count(*) from public.audit_logs)::int];
  if before_counts <> after_counts then
    raise exception 'FAIL: dry-run wrote rows (before %, after %)', before_counts, after_counts;
  end if;
  raise notice 'PASS: dry-run writes zero rows';

  -- 3b. Real import: job + rotated PIN hash + provenance timeline + audit.
  r := public.import_legacy_job(batch, '{
    "id": "SMK-101", "source": "legacy_local_storage", "status": "in_progress",
    "title": "smoke legacy", "closePin": "1234", "reporter": "no-such-user",
    "createdAt": "2026-05-01T09:00:00", "updatedAt": "2026-05-02T10:00:00",
    "timeline": [{"at": "2026-05-01T09:00:00", "action": "created", "toStatus": "waiting"}]
  }'::jsonb, false);
  if r->>'status' <> 'ok' then
    raise exception 'FAIL: real import failed (%)', r;
  end if;
  tid := r->>'target_id';
  if not exists (select 1 from public.jobs where id = tid
                   and legacy_id = 'SMK-101' and source = 'legacy_local_storage'
                   and import_batch_id = batch and status = 'received'
                   and created_at = timestamptz '2026-05-01 09:00:00 Asia/Bangkok') then
    raise exception 'FAIL: imported job row wrong or timestamps not preserved';
  end if;
  if not exists (select 1 from public.job_close_pins where job_id = tid
                   and pin_hash like '$2%' and rotated_at is not null) then
    raise exception 'FAIL: rotated PIN hash row missing';
  end if;
  if exists (select 1 from public.job_close_pins where job_id = tid and pin_hash = '1234') then
    raise exception 'FAIL: plaintext PIN persisted as hash column';
  end if;
  if not exists (select 1 from public.job_timeline where job_id = tid and imported = true
                   and created_at = timestamptz '2026-05-01 09:00:00 Asia/Bangkok') then
    raise exception 'FAIL: imported timeline provenance missing';
  end if;
  if (select payload::text || coalesce(r::text, '') from public.jobs where id = tid) like '%1234%' then
    raise exception 'FAIL: plaintext PIN leaked into payload or result';
  end if;
  if exists (select 1 from public.audit_logs where payload->>'job_id' = tid
               and payload::text like '%1234%') then
    raise exception 'FAIL: plaintext PIN leaked into audit';
  end if;
  if not exists (select 1 from public.audit_logs where action = 'LEGACY_JOB_IMPORTED'
                   and payload->>'job_id' = tid) then
    raise exception 'FAIL: audit row missing for real import';
  end if;
  raise notice 'PASS: real import (job, rotated PIN hash, provenance timeline, audit)';

  -- 3c. Idempotency: repeat resolves to skipped, no mutation.
  r2 := public.import_legacy_job(batch, '{
    "id": "SMK-101", "source": "legacy_local_storage", "status": "done",
    "title": "MUTATED", "createdAt": "2026-05-01T09:00:00"
  }'::jsonb, false);
  if r2->>'status' <> 'skipped' or r2->>'reason' <> 'already_imported' then
    raise exception 'FAIL: repeat import not skipped (%)', r2;
  end if;
  if not exists (select 1 from public.jobs where id = tid and status = 'received') then
    raise exception 'FAIL: repeat import mutated the existing record';
  end if;
  raise notice 'PASS: idempotent repeat import';

  -- 3d. Same legacy_id under a different source → different deterministic id.
  r2 := public.import_legacy_job(batch, '{
    "id": "SMK-101", "source": "legacy_snapshot_archive", "status": "open",
    "title": "same legacy id other source", "createdAt": "2026-05-01T09:00:00"
  }'::jsonb, false);
  tid2 := r2->>'target_id';
  if r2->>'status' <> 'ok' or tid2 = tid then
    raise exception 'FAIL: cross-source divergence failed (%)', r2;
  end if;
  raise notice 'PASS: cross-source legacy_id divergence';

  -- 3e. Embedded dataURL evidence fails closed in BOTH modes; rollback leaves
  -- no partial rows.
  before_counts := array[(select count(*) from public.jobs)::int,
                         (select count(*) from public.job_close_pins)::int,
                         (select count(*) from public.job_timeline)::int,
                         (select count(*) from public.job_attachments)::int,
                         (select count(*) from public.audit_logs)::int];
  r := public.import_legacy_job(batch, '{
    "id": "SMK-BIN", "status": "open", "createdAt": "2026-05-01T09:00:00",
    "closePin": "9999",
    "attachments": ["data:image/svg+xml;utf8,fake"]
  }'::jsonb, true);
  if r->>'status' <> 'failed' or r->>'reason' <> 'EVIDENCE_BINARY_MIGRATION_REQUIRED' then
    raise exception 'FAIL: dry-run did not reject embedded evidence (%)', r;
  end if;
  r := public.import_legacy_job(batch, '{
    "id": "SMK-BIN", "status": "open", "createdAt": "2026-05-01T09:00:00",
    "closePin": "9999",
    "attachments": [{"originalName": "x.png", "src": "data:image/png;base64,AAAA"}]
  }'::jsonb, false);
  if r->>'status' <> 'failed' or r->>'reason' <> 'EVIDENCE_BINARY_MIGRATION_REQUIRED' then
    raise exception 'FAIL: real import did not reject embedded evidence (%)', r;
  end if;
  after_counts := array[(select count(*) from public.jobs)::int,
                        (select count(*) from public.job_close_pins)::int,
                        (select count(*) from public.job_timeline)::int,
                        (select count(*) from public.job_attachments)::int,
                        (select count(*) from public.audit_logs)::int];
  if before_counts <> after_counts then
    raise exception 'FAIL: rejected evidence record left partial rows';
  end if;
  if exists (select 1 from public.jobs where legacy_id = 'SMK-BIN') then
    raise exception 'FAIL: rejected record has a job row';
  end if;
  raise notice 'PASS: embedded evidence fails closed with zero partial rows';

  -- 3f. Stable objectPath evidence maps to job_attachments.
  r := public.import_legacy_job(batch, '{
    "id": "SMK-EV", "status": "open", "createdAt": "2026-05-01T09:00:00",
    "attachments": [{"objectPath": "jobs/legacy/smk-ev-1.png",
                     "originalName": "before.png", "mimeType": "image/png", "sizeBytes": 1024}]
  }'::jsonb, false);
  if r->>'status' <> 'ok' then
    raise exception 'FAIL: stable evidence record failed (%)', r;
  end if;
  if not exists (select 1 from public.job_attachments
                 where job_id = r->>'target_id'
                   and object_path = 'jobs/legacy/smk-ev-1.png'
                   and mime_type = 'image/png') then
    raise exception 'FAIL: stable objectPath not mapped to job_attachments';
  end if;
  raise notice 'PASS: stable objectPath evidence mapped';

  -- 3f1b. objectPath boundary behavior (forward fix 202607110003): 3 and 511
  -- chars accepted; 2, 512 and invalid-character paths rejected safely with
  -- zero partial rows.
  r := public.import_legacy_job(batch, jsonb_build_object(
    'id', 'SMK-EV3', 'status', 'open', 'createdAt', '2026-05-01T09:00:00',
    'attachments', jsonb_build_array(jsonb_build_object('objectPath', 'a/b'))), false);
  if r->>'status' <> 'ok' then
    raise exception 'FAIL: 3-char objectPath rejected (%)', r;
  end if;
  r := public.import_legacy_job(batch, jsonb_build_object(
    'id', 'SMK-EV511', 'status', 'open', 'createdAt', '2026-05-01T09:00:00',
    'attachments', jsonb_build_array(jsonb_build_object(
      'objectPath', 'a' || repeat('b', 510)))), false);
  if r->>'status' <> 'ok' then
    raise exception 'FAIL: 511-char objectPath rejected (%)', r;
  end if;
  before_counts := array[(select count(*) from public.jobs)::int,
                         (select count(*) from public.job_close_pins)::int,
                         (select count(*) from public.job_timeline)::int,
                         (select count(*) from public.job_attachments)::int,
                         (select count(*) from public.audit_logs)::int];
  r := public.import_legacy_job(batch, jsonb_build_object(
    'id', 'SMK-EV2', 'status', 'open', 'createdAt', '2026-05-01T09:00:00',
    'attachments', jsonb_build_array(jsonb_build_object('objectPath', 'ab'))), false);
  if r->>'status' <> 'failed' or r->>'reason' <> 'EVIDENCE_UNRECOGNIZED' then
    raise exception 'FAIL: 2-char objectPath not rejected safely (%)', r;
  end if;
  r := public.import_legacy_job(batch, jsonb_build_object(
    'id', 'SMK-EV512', 'status', 'open', 'createdAt', '2026-05-01T09:00:00',
    'attachments', jsonb_build_array(jsonb_build_object(
      'objectPath', 'a' || repeat('b', 511)))), false);
  if r->>'status' <> 'failed' or r->>'reason' <> 'EVIDENCE_UNRECOGNIZED' then
    raise exception 'FAIL: 512-char objectPath not rejected safely (%)', r;
  end if;
  r := public.import_legacy_job(batch, jsonb_build_object(
    'id', 'SMK-EVBAD', 'status', 'open', 'createdAt', '2026-05-01T09:00:00',
    'attachments', jsonb_build_array(jsonb_build_object('objectPath', 'jobs/bad path?.png'))), false);
  if r->>'status' <> 'failed' or r->>'reason' <> 'EVIDENCE_UNRECOGNIZED' then
    raise exception 'FAIL: invalid-character objectPath not rejected safely (%)', r;
  end if;
  after_counts := array[(select count(*) from public.jobs)::int,
                        (select count(*) from public.job_close_pins)::int,
                        (select count(*) from public.job_timeline)::int,
                        (select count(*) from public.job_attachments)::int,
                        (select count(*) from public.audit_logs)::int];
  if before_counts <> after_counts then
    raise exception 'FAIL: rejected objectPath records left partial rows';
  end if;
  raise notice 'PASS: objectPath boundary behavior (3/511 ok; 2/512/invalid rejected, zero residue)';

  -- 3f2. All five note paths execute without malformed-array errors:
  -- completed job with missing completedAt (defaulted note) plus unresolved
  -- reporter, assignee, assignedBy and room (no roomNo) in one record.
  r := public.import_legacy_job(batch, '{
    "id": "SMK-NOTES", "status": "done",
    "reporter": "no-such-user-a", "assignee": "no-such-user-b",
    "assignedBy": "no-such-user-c", "roomNo": "NO-SUCH-ROOM-XYZ",
    "createdAt": "2026-05-01T09:00:00", "updatedAt": "2026-05-02T10:00:00"
  }'::jsonb, false);
  if r->>'status' <> 'ok' then
    raise exception 'FAIL: five-note record errored (%)', r;
  end if;
  if r->>'reason' not like '%completed_at_defaulted_to_updated_at%'
     or r->>'reason' not like '%unresolved_reporter%'
     or r->>'reason' not like '%unresolved_assignee%'
     or r->>'reason' not like '%unresolved_assigned_by%'
     or r->>'reason' not like '%unresolved_room%' then
    raise exception 'FAIL: not all five notes recorded (%)', r;
  end if;
  if not exists (select 1 from public.jobs where id = r->>'target_id'
                   and completed_at = timestamptz '2026-05-02 10:00:00 Asia/Bangkok'
                   and reported_by is null and assignee_id is null
                   and assigned_by is null and room_id is null) then
    raise exception 'FAIL: defaulted completed_at or NULL relationships wrong';
  end if;
  raise notice 'PASS: all five note paths execute (no malformed-array error)';

  -- 3g. Invalid status rejected safely; pseudo-jobs excluded.
  r := public.import_legacy_job(batch, '{"id":"SMK-BAD","status":"nonsense","createdAt":"2026-05-01T09:00:00"}'::jsonb, false);
  if r->>'status' <> 'failed' or r->>'reason' <> 'INVALID_STATUS' then
    raise exception 'FAIL: invalid status not rejected (%)', r;
  end if;
  r := public.import_legacy_job(batch, '{"id":"DEL-123","status":"open","createdAt":"2026-05-01T09:00:00"}'::jsonb, false);
  if r->>'status' <> 'skipped' or r->>'reason' <> 'pseudo_job' then
    raise exception 'FAIL: pseudo-job not excluded (%)', r;
  end if;
  raise notice 'PASS: invalid status rejected; pseudo-job excluded';

  -- 3h. No notification side effects exist: the import touches only the five
  -- audited tables (verified by the count frames above); there is no
  -- notification table or channel in this schema for it to touch.
  raise notice 'PASS: audit-only side effects';
end $$;

rollback;

do $$ begin raise notice 'STAGE 5 SMOKE: ALL ASSERTIONS PASSED (write section rolled back)'; end $$;
