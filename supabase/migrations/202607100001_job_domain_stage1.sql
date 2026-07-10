-- ============================================================================
-- Juristic Care — Stage 1: Relational job schema, RLS & RPC contract
-- Plan: docs/audit/14-strategy-b-rebuild-plan.md §3 (Stage 1), Amendment 1.
-- Contract: docs/audit/15-job-domain-rpc-contract.md
--
-- Additive only. No table is dropped, no existing column is altered or
-- removed, and no data is modified. get_app_bootstrap and
-- save_client_snapshot are intentionally NOT touched (Stage 2 / Stage 6).
--
-- What this migration does:
--   1. Provenance columns: jobs.legacy_id, jobs.import_batch_id,
--      job_timeline.imported; unique (source, legacy_id).
--   2. Privilege boundary: revoke direct anon/authenticated writes on all
--      job-domain tables; job_close_pins and google_form_submissions become
--      unreachable by clients entirely.
--   3. RLS: drop the loose jobs_insert/jobs_update policies (SEC-09);
--      authorize job_timeline / job_attachments reads through can_read_job.
--   4. Read RPC: list_jobs_for_current_user().
--   5. Write-RPC contract: create_job, assign_job, update_job_status,
--      verify_job_completion, _create_job_internal,
--      ingest_google_form_submission, import_legacy_job are re-declared as
--      FAIL-CLOSED stubs. The v1 bodies allowed completion without PIN,
--      evidence or transition checks (F-04, F-09); Stage 1 removes those
--      insecure implementations. Stage 2 supplies the enforced bodies with
--      the same signatures.
--   6. All SECURITY DEFINER functions use a fixed search_path and explicit
--      grants; PUBLIC/anon default EXECUTE is revoked.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Schema additions (provenance / legacy import support)
-- ----------------------------------------------------------------------------

alter table public.jobs
  add column if not exists legacy_id text,
  add column if not exists import_batch_id uuid;

comment on column public.jobs.legacy_id is
  'Original identifier of a job imported from a legacy store. Null for native jobs.';
comment on column public.jobs.import_batch_id is
  'Groups one import_legacy_job run. Null for native jobs.';

-- Re-running an import must never duplicate a job (plan §4).
create unique index if not exists uq_jobs_source_legacy
  on public.jobs (source, legacy_id)
  where legacy_id is not null;

create index if not exists idx_jobs_import_batch
  on public.jobs (import_batch_id)
  where import_batch_id is not null;

alter table public.job_timeline
  add column if not exists imported boolean not null default false;

comment on column public.job_timeline.imported is
  'True when the event was reconstructed by import_legacy_job rather than recorded live.';

create index if not exists idx_job_attachments_job
  on public.job_attachments (job_id, created_at desc);

-- ----------------------------------------------------------------------------
-- 2. Privilege boundary — job domain
--    v1 granted select/insert/update/delete on ALL tables to authenticated.
--    Every job write must go through a SECURITY DEFINER RPC; direct table
--    writes by anon or authenticated are denied at the privilege level
--    (defence in depth on top of RLS).
-- ----------------------------------------------------------------------------

revoke insert, update, delete, truncate, references, trigger
  on public.jobs, public.job_timeline, public.job_attachments
  from anon, authenticated;

-- PIN hashes must never be readable or writable by clients (plan §2:
-- "protect job_close_pins from direct client reads").
revoke all on public.job_close_pins from anon, authenticated;

-- Form submissions are handled exclusively by the service-role ingestion
-- boundary (Amendment 1); clients have no business reading raw payloads.
revoke all on public.google_form_submissions from anon, authenticated;

-- anon must not even read job-domain rows.
revoke select on public.jobs, public.job_timeline, public.job_attachments
  from anon;

-- ----------------------------------------------------------------------------
-- 3. RLS — job domain
-- ----------------------------------------------------------------------------

-- SEC-09: the v1 insert policy allowed any authenticated app user to insert
-- arbitrary jobs, and the update policy allowed direct status writes that
-- bypass PIN/evidence/transition rules. With no insert/update policy and no
-- table privilege, direct client writes are denied twice over.
drop policy if exists jobs_insert on public.jobs;
drop policy if exists jobs_update on public.jobs;

-- jobs_select (via can_read_job) already exists in v1 and is kept.

-- Timeline and attachments are authorized through the related job.
drop policy if exists job_timeline_select on public.job_timeline;
create policy job_timeline_select on public.job_timeline
  for select to authenticated
  using (public.can_read_job(job_id));

drop policy if exists job_attachments_select on public.job_attachments;
create policy job_attachments_select on public.job_attachments
  for select to authenticated
  using (public.can_read_job(job_id));

-- job_close_pins / google_form_submissions: RLS is enabled (v1) and no
-- policy exists for any client role → deny by default. None is added here.

-- ----------------------------------------------------------------------------
-- 4. Read RPC — list_jobs_for_current_user
-- ----------------------------------------------------------------------------

create or replace function public.list_jobs_for_current_user()
returns setof jsonb
language sql
stable
security definer
set search_path = public
as $$
  select j.payload || jsonb_build_object(
           'id',         j.id,
           'source',     j.source,
           'status',     j.status,
           'subStatus',  j.sub_status,
           'legacyId',   j.legacy_id,
           'createdAt',  j.created_at,
           'updatedAt',  j.updated_at
         )
  from public.jobs j
  where public.current_app_user_id() is not null
    and public.can_read_job(j.id)
  order by j.created_at desc
$$;

comment on function public.list_jobs_for_current_user() is
  'Stage 1 read contract: every job the caller may see per can_read_job. The only supported client job-read path from Stage 3 onward. Never exposes PIN data.';

-- ----------------------------------------------------------------------------
-- 5. Write-RPC contract — fail-closed stubs (bodies land in Stage 2 / 5)
--    The v1 implementations are removed because they let any assignee set
--    status='completed' with no PIN, evidence or transition check (F-04).
--    Signatures are frozen here; see docs/audit/15-job-domain-rpc-contract.md.
-- ----------------------------------------------------------------------------

create or replace function public.create_job(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'JOB_WRITES_UNAVAILABLE'
    using detail = 'create_job is contract-only in Stage 1; the enforced body ships in Stage 2.',
          errcode = 'P0001';
end $$;

create or replace function public.assign_job(p_job_id text, p_assignee_id uuid, p_extra jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'JOB_WRITES_UNAVAILABLE'
    using detail = 'assign_job is contract-only in Stage 1; the enforced body ships in Stage 2.',
          errcode = 'P0001';
end $$;

create or replace function public.update_job_status(p_job_id text, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'JOB_WRITES_UNAVAILABLE'
    using detail = 'update_job_status is contract-only in Stage 1; the enforced body (PIN, evidence, transitions) ships in Stage 2.',
          errcode = 'P0001';
end $$;

create or replace function public.verify_job_completion(p_job_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'JOB_WRITES_UNAVAILABLE'
    using detail = 'verify_job_completion is contract-only in Stage 1; the enforced body ships in Stage 2.',
          errcode = 'P0001';
end $$;

-- Internal shared creation path (Amendment 1). Never client-callable.
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
begin
  raise exception 'INTERNAL_ONLY'
    using detail = '_create_job_internal is the shared normalized creation path for create_job and ingest_google_form_submission; implemented in Stage 2.',
          errcode = 'P0001';
end $$;

-- Transactional Google Form ingestion boundary (Amendment 1).
-- Service-role only; the Edge Function authenticates the webhook and calls
-- this once. Stage 2 implements the single-transaction body (idempotency by
-- external_id, submission row, exactly one job, timeline, audit, rollback).
create or replace function public.ingest_google_form_submission(
  p_external_id text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'INGESTION_UNAVAILABLE'
    using detail = 'ingest_google_form_submission is contract-only in Stage 1; the transactional body ships in Stage 2 and the Form trigger stays disabled until Stage 7.',
          errcode = 'P0001';
end $$;

-- Legacy import boundary (plan §4, Amendment 3). Admin/service only.
-- Stage 5 implements dry-run, per-record reporting, count reconciliation and
-- in-DB PIN hashing/rotation. Plaintext PINs are never persisted or returned.
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
begin
  if not public.is_admin_account() then
    raise exception 'FORBIDDEN'
      using detail = 'import_legacy_job is restricted to admin or service-role callers.',
            errcode = '42501';
  end if;
  raise exception 'IMPORT_UNAVAILABLE'
    using detail = 'import_legacy_job is contract-only in Stage 1; the implementation ships in Stage 5.',
          errcode = 'P0001';
end $$;

-- ----------------------------------------------------------------------------
-- 6. Function grants — explicit, least privilege
--    (Postgres grants EXECUTE to PUBLIC by default; revoke it everywhere.)
-- ----------------------------------------------------------------------------

revoke all on function public.list_jobs_for_current_user() from public, anon;
grant execute on function public.list_jobs_for_current_user() to authenticated, service_role;

revoke all on function public.create_job(jsonb) from public, anon;
grant execute on function public.create_job(jsonb) to authenticated, service_role;

revoke all on function public.assign_job(text, uuid, jsonb) from public, anon;
grant execute on function public.assign_job(text, uuid, jsonb) to authenticated, service_role;

revoke all on function public.update_job_status(text, jsonb) from public, anon;
grant execute on function public.update_job_status(text, jsonb) to authenticated, service_role;

revoke all on function public.verify_job_completion(text) from public, anon;
grant execute on function public.verify_job_completion(text) to authenticated, service_role;

-- Internal: nobody but the definer context may call it.
revoke all on function public._create_job_internal(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public._create_job_internal(uuid, text, jsonb) to service_role;

-- Ingestion: service role only (called by the Edge Function).
revoke all on function public.ingest_google_form_submission(text, jsonb) from public, anon, authenticated;
grant execute on function public.ingest_google_form_submission(text, jsonb) to service_role;

-- Import: service role, plus authenticated so the in-body admin check can
-- return FORBIDDEN to non-admins with a clean error.
revoke all on function public.import_legacy_job(uuid, jsonb, boolean) from public, anon;
grant execute on function public.import_legacy_job(uuid, jsonb, boolean) to authenticated, service_role;
