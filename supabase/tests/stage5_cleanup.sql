-- ============================================================================
-- Stage 5 — STAGING-ONLY cleanup of ONE approved legacy import batch.
--
-- This script is INERT until an administrator edits the two constants below.
-- It must only ever be run through the STAGING connection (runbook rule; the
-- driver allowlist and the absence of any production credential in this repo
-- are the operational controls — SQL cannot detect its own project).
--
-- Behavior: single transaction; previews affected counts; verifies EVERY
-- targeted job carries the exact batch id AND a legacy source; aborts on any
-- mismatch (including dependent-row surprises); deletes only that batch
-- (children via FK cascade); re-verifies counts after deletion; records one
-- safe audit row (ids + counts only — no payload content, no PIN data).
--
-- Audit rows from the original import are DELIBERATELY RETAINED: audit_logs
-- is the immutable history of what happened; cleanup is itself an event and
-- is recorded as one, not an eraser of prior events.
-- ============================================================================

begin;

do $$
declare
  -- ==== ADMINISTRATOR INPUT (edit BOTH before running) =======================
  v_batch   constant text := 'FILL-IN-IMPORT-BATCH-ID';
  v_confirm constant text := 'FILL-IN-CONFIRMATION';   -- must equal 'CLEANUP-' || v_batch
  -- ===========================================================================
  v_batch_id uuid;
  n_jobs int;
  n_pins int;
  n_timeline int;
  n_attachments int;
  n_foreign int;
begin
  if v_batch = 'FILL-IN-IMPORT-BATCH-ID' or v_confirm = 'FILL-IN-CONFIRMATION' then
    raise exception 'ABORT: fill in the import batch id and the confirmation value first';
  end if;
  if v_confirm <> 'CLEANUP-' || v_batch then
    raise exception 'ABORT: confirmation value does not match CLEANUP-<batch-id>';
  end if;
  v_batch_id := v_batch::uuid;

  -- ---- PREVIEW --------------------------------------------------------------
  select count(*) into n_jobs from public.jobs where import_batch_id = v_batch_id;
  if n_jobs = 0 then
    raise exception 'ABORT: no jobs found for batch % — nothing to clean', v_batch_id;
  end if;
  -- Every targeted job must be a legacy import of this exact batch.
  select count(*) into n_foreign from public.jobs
  where import_batch_id = v_batch_id
    and (legacy_id is null or source not like 'legacy_%');
  if n_foreign > 0 then
    raise exception 'ABORT: % job(s) in batch % are not legacy-sourced — refusing to delete anything',
      n_foreign, v_batch_id;
  end if;
  select count(*) into n_pins from public.job_close_pins p
  join public.jobs j on j.id = p.job_id where j.import_batch_id = v_batch_id;
  select count(*) into n_timeline from public.job_timeline t
  join public.jobs j on j.id = t.job_id where j.import_batch_id = v_batch_id;
  -- Imported timeline rows must all carry provenance; anything else means the
  -- batch was touched by live workflows and must be reviewed, not deleted.
  if exists (select 1 from public.job_timeline t
             join public.jobs j on j.id = t.job_id
             where j.import_batch_id = v_batch_id and t.imported = false) then
    raise exception 'ABORT: batch % has non-imported timeline rows (live activity) — manual review required', v_batch_id;
  end if;
  select count(*) into n_attachments from public.job_attachments a
  join public.jobs j on j.id = a.job_id where j.import_batch_id = v_batch_id;

  raise notice 'PREVIEW batch %: jobs=% pins=% timeline=% attachments=%',
    v_batch_id, n_jobs, n_pins, n_timeline, n_attachments;

  -- ---- DELETE (children cascade from jobs) ----------------------------------
  delete from public.jobs where import_batch_id = v_batch_id;

  -- ---- VERIFY ---------------------------------------------------------------
  if exists (select 1 from public.jobs where import_batch_id = v_batch_id) then
    raise exception 'ABORT: jobs remain after delete — rolling back';
  end if;
  if exists (select 1 from public.job_timeline t
             left join public.jobs j on j.id = t.job_id where j.id is null) then
    raise exception 'ABORT: orphan timeline rows detected — rolling back';
  end if;
  if exists (select 1 from public.job_attachments a
             left join public.jobs j on j.id = a.job_id where j.id is null) then
    raise exception 'ABORT: orphan attachment rows detected — rolling back';
  end if;

  -- ---- SAFE AUDIT RECORD (ids + counts only) --------------------------------
  insert into public.audit_logs (actor_role, action, detail, payload)
  values ('system', 'LEGACY_IMPORT_CLEANUP',
          'Staging cleanup of import batch ' || v_batch_id,
          jsonb_build_object('import_batch_id', v_batch_id,
                             'jobs_deleted', n_jobs, 'pins_deleted', n_pins,
                             'timeline_deleted', n_timeline,
                             'attachments_deleted', n_attachments));
  raise notice 'CLEANUP OK: batch % removed (jobs=% pins=% timeline=% attachments=%). COMMIT to finalize.',
    v_batch_id, n_jobs, n_pins, n_timeline, n_attachments;
end $$;

-- The administrator reviews the notices above, then finalizes explicitly:
commit;
