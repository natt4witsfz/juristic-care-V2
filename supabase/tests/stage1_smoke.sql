-- ============================================================================
-- Stage 1 smoke test — structural assertions for
-- supabase/migrations/202607100001_job_domain_stage1.sql
--
-- Run against a STAGING database that has both migrations applied, either:
--   * Supabase SQL Editor: paste the whole file and run (plain SQL only —
--     no psql meta-commands are used), or
--   * psql: psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 \
--            -f supabase/tests/stage1_smoke.sql
--
-- Read-only: only DO-block assertions; writes nothing. Every failed
-- assertion raises, so a clean run (ending with the final notice) means PASS.
-- Status: a staging project exists, but no migration has been applied to it
-- yet, and this smoke test has not yet been run against PostgreSQL.
-- ============================================================================

-- 1. Provenance schema additions ---------------------------------------------
do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'jobs'
                   and column_name = 'legacy_id') then
    raise exception 'FAIL: jobs.legacy_id missing';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'jobs'
                   and column_name = 'import_batch_id') then
    raise exception 'FAIL: jobs.import_batch_id missing';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'jobs'
                   and column_name = 'raw') then
    raise exception 'FAIL: jobs.raw missing';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'jobs'
                   and column_name = 'raw' and data_type = 'boolean') then
    raise exception 'FAIL: jobs.raw is not boolean (must be a triage flag, not a payload)';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'jobs'
                   and column_name = 'raw' and is_nullable = 'NO') then
    raise exception 'FAIL: jobs.raw is nullable (must be NOT NULL)';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'jobs'
                   and column_name = 'raw'
                   and column_default ilike '%false%') then
    raise exception 'FAIL: jobs.raw default is not false';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'jobs'
                   and column_name = 'completed_at') then
    raise exception 'FAIL: jobs.completed_at missing';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'jobs'
                   and column_name = 'completed_at'
                   and data_type = 'timestamp with time zone') then
    raise exception 'FAIL: jobs.completed_at is not timestamptz';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'job_timeline'
                   and column_name = 'imported') then
    raise exception 'FAIL: job_timeline.imported missing';
  end if;
  if not exists (select 1 from pg_indexes
                 where schemaname = 'public' and tablename = 'jobs'
                   and indexname = 'uq_jobs_source_legacy'
                   and indexdef ilike '%unique%') then
    raise exception 'FAIL: unique index uq_jobs_source_legacy missing';
  end if;
  if not exists (select 1 from pg_indexes
                 where schemaname = 'public' and tablename = 'jobs'
                   and indexname = 'idx_jobs_raw_open') then
    raise exception 'FAIL: partial index idx_jobs_raw_open missing';
  end if;
  -- The predicate must scope the index to the raw-intake triage pool.
  if not exists (select 1 from pg_indexes
                 where schemaname = 'public' and tablename = 'jobs'
                   and indexname = 'idx_jobs_raw_open'
                   and indexdef ilike '%raw = true%') then
    raise exception 'FAIL: idx_jobs_raw_open predicate lacks raw = true';
  end if;
  if not exists (select 1 from pg_indexes
                 where schemaname = 'public' and tablename = 'jobs'
                   and indexname = 'idx_jobs_raw_open'
                   and indexdef ilike '%status = ''open''%') then
    raise exception 'FAIL: idx_jobs_raw_open predicate lacks status = ''open''';
  end if;
  raise notice 'PASS: provenance schema additions';
end $$;

-- 2. Privilege boundary: no direct client writes on job domain ---------------
do $$
declare
  t text;
  p text;
begin
  foreach t in array array['jobs','job_timeline','job_attachments',
                           'job_close_pins','google_form_submissions'] loop
    foreach p in array array['INSERT','UPDATE','DELETE'] loop
      if has_table_privilege('anon', 'public.' || t, p)
         or has_table_privilege('authenticated', 'public.' || t, p) then
        raise exception 'FAIL: client role holds % on %', p, t;
      end if;
    end loop;
  end loop;
  if has_table_privilege('anon', 'public.job_close_pins', 'SELECT')
     or has_table_privilege('authenticated', 'public.job_close_pins', 'SELECT') then
    raise exception 'FAIL: job_close_pins is client-readable';
  end if;
  if has_table_privilege('authenticated', 'public.google_form_submissions', 'SELECT') then
    raise exception 'FAIL: google_form_submissions is client-readable';
  end if;
  if has_table_privilege('anon', 'public.jobs', 'SELECT') then
    raise exception 'FAIL: anon can SELECT jobs';
  end if;
  raise notice 'PASS: job-domain write/read privileges revoked from clients';
end $$;

-- 3. RLS state and policies ---------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['jobs','job_close_pins','job_timeline',
                           'job_attachments','google_form_submissions'] loop
    if not exists (select 1 from pg_class c
                   join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relname = t
                     and c.relrowsecurity) then
      raise exception 'FAIL: RLS not enabled on %', t;
    end if;
  end loop;
  -- loose v1 write policies must be gone (SEC-09)
  if exists (select 1 from pg_policies where schemaname = 'public'
               and tablename = 'jobs' and policyname in ('jobs_insert','jobs_update')) then
    raise exception 'FAIL: loose jobs_insert/jobs_update policy still present';
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                   and tablename = 'jobs' and policyname = 'jobs_select') then
    raise exception 'FAIL: jobs_select policy missing';
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                   and tablename = 'job_timeline' and policyname = 'job_timeline_select'
                   and qual like '%can_read_job%') then
    raise exception 'FAIL: job_timeline_select via can_read_job missing';
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                   and tablename = 'job_attachments' and policyname = 'job_attachments_select'
                   and qual like '%can_read_job%') then
    raise exception 'FAIL: job_attachments_select via can_read_job missing';
  end if;
  -- pins/submissions: deny-by-default (no policy of any kind)
  if exists (select 1 from pg_policies where schemaname = 'public'
               and tablename in ('job_close_pins','google_form_submissions')) then
    raise exception 'FAIL: unexpected policy on job_close_pins/google_form_submissions';
  end if;
  raise notice 'PASS: RLS policies match the Stage 1 contract';
end $$;

-- 4. Functions: existence, SECURITY DEFINER, fixed search_path ----------------
do $$
declare
  f record;
begin
  for f in
    select * from (values
      ('list_jobs_for_current_user'),
      ('create_job'),
      ('assign_job'),
      ('update_job_status'),
      ('verify_job_completion'),
      ('_create_job_internal'),
      ('ingest_google_form_submission'),
      ('import_legacy_job')
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
  raise notice 'PASS: all Stage 1 functions are SECURITY DEFINER with fixed search_path';
end $$;

-- 4b. Read contract: relational authority is complete and never stripped ------
do $$
declare
  src text;
begin
  select p.prosrc into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'list_jobs_for_current_user';
  if src is null then
    raise exception 'FAIL: list_jobs_for_current_user source not found';
  end if;
  if src not ilike '%''raw''%' then
    raise exception 'FAIL: list_jobs_for_current_user output contract omits raw';
  end if;
  if src ilike '%jsonb_strip_nulls%' then
    raise exception 'FAIL: list_jobs_for_current_user uses jsonb_strip_nulls (relational NULLs must override stale payload values)';
  end if;
  raise notice 'PASS: read contract includes raw and does not strip relational nulls';
end $$;

-- 5. Function grants: internal/ingestion not client-callable ------------------
do $$
begin
  if has_function_privilege('authenticated',
       'public._create_job_internal(uuid, text, jsonb)', 'EXECUTE')
     or has_function_privilege('anon',
       'public._create_job_internal(uuid, text, jsonb)', 'EXECUTE')
     or has_function_privilege('service_role',
       'public._create_job_internal(uuid, text, jsonb)', 'EXECUTE') then
    raise exception 'FAIL: _create_job_internal is directly executable (must be definer-context only)';
  end if;
  if has_function_privilege('authenticated',
       'public.ingest_google_form_submission(text, jsonb)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.ingest_google_form_submission(text, jsonb)', 'EXECUTE') then
    raise exception 'FAIL: ingest_google_form_submission is client-executable';
  end if;
  if has_function_privilege('anon',
       'public.create_job(jsonb)', 'EXECUTE') then
    raise exception 'FAIL: anon can execute create_job';
  end if;
  if not has_function_privilege('authenticated',
       'public.list_jobs_for_current_user()', 'EXECUTE') then
    raise exception 'FAIL: authenticated cannot execute list_jobs_for_current_user';
  end if;
  raise notice 'PASS: function grants match the Stage 1 contract';
end $$;

-- 6. Write stubs fail closed ---------------------------------------------------
do $$
begin
  begin
    perform public.create_job('{}'::jsonb);
    raise exception 'FAIL: create_job did not fail closed';
  exception when others then
    if sqlerrm not like '%JOB_WRITES_UNAVAILABLE%' then
      raise exception 'FAIL: create_job raised unexpected error: %', sqlerrm;
    end if;
  end;
  begin
    perform public.update_job_status('nonexistent', '{"status":"completed"}'::jsonb);
    raise exception 'FAIL: update_job_status did not fail closed';
  exception when others then
    if sqlerrm not like '%JOB_WRITES_UNAVAILABLE%' then
      raise exception 'FAIL: update_job_status raised unexpected error: %', sqlerrm;
    end if;
  end;
  begin
    perform public.ingest_google_form_submission('smoke-x', '{}'::jsonb);
    raise exception 'FAIL: ingest_google_form_submission did not fail closed';
  exception when others then
    if sqlerrm not like '%INGESTION_UNAVAILABLE%' then
      raise exception 'FAIL: ingest_google_form_submission raised unexpected error: %', sqlerrm;
    end if;
  end;
  raise notice 'PASS: write RPCs fail closed (Stage 1 stubs)';
end $$;

do $$ begin raise notice 'STAGE 1 SMOKE: ALL ASSERTIONS PASSED'; end $$;
