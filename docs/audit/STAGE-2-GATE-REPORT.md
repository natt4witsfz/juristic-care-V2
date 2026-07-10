# STAGE 2 GATE REPORT — Server-enforced job workflow

> Date: 2026-07-10 · Branch: `feat/stage-2-server-workflow` · Baseline:
> Stage 1 closed and tagged `stage-1-staging-verified` (commit `be84178`;
> migrations `202607090001`, `202607100001`, `202607100002` applied to
> staging, histories in sync, db lint clean, `stage1_smoke.sql` all
> assertions passed), with the three Stage 1 fix commits cherry-picked onto
> this branch. Per the stage-gate protocol in
> `docs/audit/14-strategy-b-rebuild-plan.md` §7.
> **Status: STAGE 2 GATE APPROVED — runtime-verified on staging 2026-07-10
> (see §10). Hard stop — Stage 3 not started. Frontend untouched. Form
> trigger disabled.**

## 1. Files changed

| File | Change |
| --- | --- |
| `supabase/migrations/202607100003_job_domain_stage2.sql` | **New** — Stage 2 migration (enforced RPC bodies, workflow helpers, bootstrap fix). Renamed from version `202607100002` because that version number is taken by the applied Stage 1 pgcrypto forward fix; exactly one migration exists per version. |
| `supabase/tests/stage2_smoke.sql` | **New** — structural + rolled-back behavioral assertions for staging |
| `docs/audit/15-job-domain-rpc-contract.md` | Updated — availability matrix now reflects enforced Stage 2 bodies; legal-transition table documented; one-time `closePin` disclosure documented |
| `docs/audit/STAGE-2-GATE-REPORT.md` | **New** — this report |

Explicitly untouched: all frontend files (`app.js`, `profiles.js`,
`supabase-client.js`, `config.js`, `index.html`, UI/CSS/DOM), `SUPABASE_ENABLED`
(remains false), the Google Form trigger (remains disabled), all Edge
Functions, `save_client_snapshot`, `import_legacy_job` (still the Stage 1
fail-closed stub until Stage 5), `list_jobs_for_current_user` (unchanged from
Stage 1), Stage 0/1 migrations and `stage1_smoke.sql`.

## 2. Migration changes (`202607100003_job_domain_stage2.sql`)

All Stage 1 signatures, grants and the privilege/RLS boundary are unchanged
(`CREATE OR REPLACE` preserves ACLs). What the enforced bodies add:

1. **Workflow helpers (internal-only; EXECUTE revoked from client roles):**
   `_bkk_date` / `_bkk_today` (Asia/Bangkok date normalization — a
   near-midnight UTC timestamp maps to the correct Bangkok calendar day),
   `_clean_text` (NUL-strip, trim, length caps → `INVALID_INPUT`),
   `_is_legal_job_transition` (the single legal-transition table),
   `_job_read_jsonb` (single-job client read shape, key-for-key identical to
   `list_jobs_for_current_user`, relational NULLs never stripped),
   `_store_job_evidence` (1–3 photos by status, ≤5MB, png/jpeg/webp only,
   rows written to `job_attachments` tied to the timeline event).
2. **`_create_job_internal(actor, source, payload)`** — the one shared
   normalized creation path (Amendment 1): whitelisted payload keys only
   (caller can never set id/status/subStatus/raw/completedAt/verifier/admin
   fields); server-generated `JC-`/`GF-` id (Bangkok date + random suffix,
   collision-checked); `raw = true` when unassigned (triage pool); close PIN
   generated from pgcrypto randomness and stored **only** as a bcrypt hash;
   initial `job_timeline` (+ `assigned` event if created assigned) and
   `audit_logs` in the same transaction; `closePin` returned exactly once and
   only for WebApp creations.
3. **`create_job`** — `AUTH_REQUIRED` without an active app account;
   idempotency-key retry returns the existing job (`duplicate: true`, no PIN);
   delegates to `_create_job_internal` with `source = 'WebApp'`.
4. **`assign_job`** — admin, or `can_assign` staff with `can_update_job`;
   assignee must be an active staff account; transition validated
   (`open`/working → `received`); sets `raw = false`; row locked
   (`FOR UPDATE`); timeline + audit.
5. **`update_job_status`** — the F-04 fix: target status must be in the
   vocabulary and the transition legal (`ILLEGAL_TRANSITION`); per-status
   required inputs (inspectionDate / nextUpdateDate / updateDate+cause+solution);
   **`completed` requires `crypt(pin, pin_hash) = pin_hash`** against
   `job_close_pins` (`PIN_INVALID`, job unchanged); **`noPinAvailable = true`
   forces `pending_inspection` + `waiting_owner_or_admin_verification`**,
   requires `noPinReason` and ≥1 photo, and never returns `completed`;
   evidence enforced server-side (≥1 photo unless target is
   `received`/`rejected`, max 3); `nextUpdateDate` only overwritten when the
   key is present (DB-03); `completed_at` set server-side only; timeline +
   audit on every transition.
6. **`verify_job_completion`** — verifier must be admin/co-admin, the
   assigner, or the reporting room's resident account (never the mere
   assignee); valid only from `pending_inspection` +
   `waiting_owner_or_admin_verification`; sets `completed` + server
   `completed_at`; timeline + audit.
7. **`ingest_google_form_submission`** — service-role only (Stage 1 grant);
   one plpgsql function = **one transaction**: idempotency by `external_id`
   (retry returns the existing job with `duplicate: true`), the verbatim
   untrusted payload stored in `google_form_submissions.payload` (never on
   the job — `jobs.raw` stays a boolean triage flag), exactly one `raw = true`
   `open` job via `_create_job_internal` (webhook can never set actor,
   assignee, status, completed, verifier or admin fields), timeline + audit,
   full rollback on any failure. **The Form trigger remains disabled until
   Stage 7.**
8. **`get_app_bootstrap`** — jobs are **never** served from `app_snapshots`:
   the `jobs` key is always rebuilt from the relational read path
   (`can_read_job`, same shape as `list_jobs_for_current_user`); a staff
   snapshot, when present, is returned with its `jobs` key stripped and
   replaced. Non-job domains still ride the snapshot until Stage 6, as
   planned.

Immutability: `job_timeline` and `audit_logs` remain client-unwritable
(Stage 1 privilege revocation + no write policies; `audit_logs` also carries
the v1 no-update/no-delete policies). Only the SECURITY DEFINER RPCs write
them.

## 3. Known supersession

`stage1_smoke.sql` §6 asserts the Stage 1 fail-closed stubs
(`JOB_WRITES_UNAVAILABLE` / `INGESTION_UNAVAILABLE`). Once this migration is
applied, those stubs no longer exist **by design**, so that one section will
fail if re-run; `stage2_smoke.sql` §2 supersedes it (asserts the stubs are
gone and the enforcement markers are present). Sections 1–5 of the Stage 1
smoke remain valid and should still pass.

## 4. Commands run and actual results

| Command | Result |
| --- | --- |
| `npm run check` | **PASS** — all 5 JS files pass `node --check` |
| `npm test` | **PASS** — 35 tests: 14 pass, 0 fail, 21 todo (unchanged; the 8 Stage 2 markers need a live DB and are encoded in `stage2_smoke.sql`) |
| `git diff --check` | clean |
| Structural SQL validation (node script) | dollar-quoting balanced, parentheses balanced, 0 psql meta-commands in both new SQL files |
| `supabase db push` / staging | **NOT run** — the Stage 2 migration has not been applied anywhere |

## 5. Tests — passing / pending / failing

- **Passing (14):** all Stage 0 active tests, unchanged.
- **Pending by stage (21 todo):** unchanged. The eight Stage 2 markers
  (PIN rejection, no-PIN → pending_inspection + waiting_verification,
  evidence enforcement, illegal-transition rejection, timeline+audit on every
  transition, Bangkok midnight boundary, transactional ingestion rollback,
  bootstrap never serving snapshot jobs) require a live database; their
  server-side assertions are encoded in `supabase/tests/stage2_smoke.sql`
  (structural sections + a BEGIN/ROLLBACK write round-trip that persists
  nothing).
- **Genuinely failing: 0.**

## 6. Not runtime-verified (declared limits)

- Migration `202607100003` has **not** been applied to any database; no
  PostgreSQL parsed or executed it. Validation is structural only.
- `stage2_smoke.sql` has **not** been executed.
- PIN/bcrypt behavior, transition rejection, evidence enforcement, ingestion
  rollback and the bootstrap fix are asserted by design + smoke script until
  the staging dry-run is approved and run.

## 7. Rollback point

Nothing applied anywhere. Local rollback: delete the two new SQL files and
this report, revert the contract doc (`git checkout 61e6a59 -- docs/audit/15-job-domain-rpc-contract.md`),
or `git revert` the Stage 2 commit once created. If later applied to staging
and it must be undone: re-run migration `202607100001` section 5 to restore
the Stage 1 fail-closed stubs (same signatures), drop the Stage 2 helper
functions, and restore the v1 `get_app_bootstrap` body — a down script can be
produced before the staging apply if required.

## 7a. Post-apply addendum (2026-07-10) — _clean_text chr(0) fix

- Migration `202607100003_job_domain_stage2.sql` **was applied successfully
  to staging**.
- The linked **db lint then failed** on `public._clean_text`:
  `null character not permitted` (assignment to variable `v`). Root cause:
  the installed body used `btrim(replace(p_value, chr(0), ''))`, but
  PostgreSQL `text` can never contain the zero byte — constructing `chr(0)`
  itself raises this error, and the replacement is unnecessary because a NUL
  can never be present in a `text` parameter.
- **The Stage 2 gate is NOT yet approved.**
- The correction is a **new forward migration**,
  `supabase/migrations/202607100004_clean_text_null_fix.sql`, redefining only
  `_clean_text` with `v := btrim(p_value)` while preserving its signature,
  return type, language, IMMUTABLE attribute, fixed `search_path = public`,
  trimming, empty-string→NULL behavior, length validation and
  `INVALID_INPUT` error behavior. A search of all migrations confirmed no
  other currently-active function contains the defect.
- The already-applied migration file was **not rewritten**; no migration
  repair was used.
- `stage2_smoke.sql` gained section 5b (trim/NULL/length/INVALID_INPUT
  behavior plus source assertions that no `chr(0)` or null-character
  replacement remains); its write section stays inside BEGIN/ROLLBACK. The
  Stage 2 smoke test has **not yet been executed**; db lint is not claimed
  fixed until `202607100004` is applied and the lint reruns clean.

## 8. Confirmation — no Supabase resource modified

No migration was applied, no `supabase db push`, no smoke test executed
against a database, no Edge Function deployed or edited, no trigger enabled,
no secret handled, no production or staging resource touched. All Stage 2
output is files in this repository. `SUPABASE_ENABLED` remains false; Google
Form ingestion remains disabled.

## 10. Final runtime verification on staging (2026-07-10) — GATE APPROVED

Stage 2 has been runtime-verified successfully on the staging Supabase
project (fake data only):

- Migration `202607100003_job_domain_stage2` **applied successfully**.
- Forward fix `202607100004_clean_text_null_fix` **applied successfully**
  (resolving the §7a db lint finding).
- Local and remote migration histories **match through `202607100004`**.
- Linked database lint **passed** (ERRORLEVEL = 0).
- `supabase/tests/stage2_smoke.sql` **completed successfully with no failed
  assertions** — enforced bodies installed (PIN, no-PIN fallback,
  transitions, evidence), bootstrap never serves snapshot jobs, transition
  table and Asia/Bangkok normalization behave as specified, `_clean_text`
  section 5b passes, and the transactional ingestion round-trip (idempotency,
  exactly one raw=true job + PIN + timeline + audit, no PIN leakage)
  succeeded with its **write section rolled back**.
- No production project or real resident data was touched.
- `SUPABASE_ENABLED` remains **false**; the Google Form trigger remains
  **disabled**; Stage 3 has **not** started.

The declared limits in §6 are hereby closed: the Stage 2 workflow boundary is
now observed live, not just asserted by design. **The Stage 2 gate is
approved**; this state is tagged `stage-2-staging-verified`. The next step is
Stage 3 (frontend relational read path), which does not begin without
explicit approval.

## 9. Approval request (historical — superseded by §10)

**Go/no-go:**
1. Approve one commit of the Stage 2 review-preparation changes to
   `feat/stage-2-server-workflow`.
2. Approve applying `202607100003_job_domain_stage2.sql` to the **staging**
   project and running `supabase/tests/stage2_smoke.sql` there (its write
   section is wrapped in BEGIN/ROLLBACK and persists nothing).

Stage 3 (frontend relational read path) will not begin without explicit
approval.
