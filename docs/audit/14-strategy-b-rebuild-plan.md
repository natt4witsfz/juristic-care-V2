# 14 — Strategy B Rebuild Plan (Job Domain) — Approved, Revised

> Status: **approved plan, pre-implementation.** No source code changed. Incorporates all ten mandatory corrections. Labels: **[FACT]** verified from code, **[RISK]**, **[ASSUMPTION]**, **[REC]**. Constraints honored: no production, no production data, no UI/CSS redesign, no from-zero rewrite, scoped to the job domain.

---

## 1. Revised Architecture Decision

**[REC] Adopt Strategy B — Controlled Core Rebuild of the job domain — with a strict single-authority rule and a one-way, read-before-write cutover.** Supabase relational tables become the only source of truth for jobs; every job write goes through an approved RPC/Edge Function; every job read comes from Supabase. localStorage is reduced to UI preferences and an isolated demo mode. The snapshot bridge is removed from the job domain entirely.

The rebuild is a **data-layer + authority-boundary** change. The visible UI, DOM, CSS, Thai/English labels, and the user-facing workflow are preserved. The in-memory `jobs` array is retained **only as a read cache** hydrated exclusively from Supabase.

**Single-authority rule (binding):**

`JOB_BACKEND = supabase`
- Job reads: **only** from Supabase (RPC/view).
- Job creates: **only** via approved RPCs / Edge Functions.
- Job updates: **only** via approved RPCs.
- localStorage jobs: **not loaded, not merged, not written.**
- Snapshot jobs: **ignored.**
- Legacy Apps Script job sync: **disabled.**
- Google Sheet: **archive/reference only.**

`JOB_BACKEND = demo-local`
- Supabase job writes: **disabled.**
- Google Form ingestion: **disabled.**
- Mode **visibly labelled "DEMO"** in the UI.
- **No real resident data permitted.**

**There is no dual-write mode. Never.** A build is in exactly one of these two states.

## 2. Final Rebuild Boundary

**In scope — job-domain authority boundary (rebuilt):**
job list & detail reads · create job · resident job submission · Google Form intake · assignment · status update · required-evidence validation · server-side PIN validation · no-PIN pending-inspection fallback · completion verification · `audit_logs` · `job_timeline` · idempotency · Asia/Bangkok job dates · job-domain authorization · job-domain tests.

**Out of scope (this phase):**
- Full resident / team / committee PII migration — **except** the minimum relationship needed for job authorization (e.g. mapping a job to a room/assignee so RLS can decide access). PII table migration proper is the next phase.
- Routine Daily Task / PM, LINE OA, Web Push, Google Calendar, finance, multi-tenant.
- UI / CSS redesign.
- Cosmetic `app.js` modularization. (Functional extraction of a `jobsApi`/`workflow` seam is allowed **only** where required to route writes through RPC.)
- Production deployment.

**Preserved (behavior & appearance unchanged):**
render functions and DOM (`jobRow`, `openJob`, `renderJobList`, dashboards, compact mode) · status set and sub-status semantics · PIN UX and no-PIN fallback UX · bilingual labels · existing relational schema + RLS (extended, not replaced) · the `jobs` array as a read cache.

## 3. Stage-by-Stage Implementation Plan

Each stage ends at a **hard stop gate** (§7). No later stage begins automatically.

### Stage 0 — Safety baseline & tests
- Add `package.json` (scripts: serve/check/lint/test), `.gitignore` (config with real values, media, node_modules), ESLint, `deno check` for Edge Functions, Vitest + Playwright scaffolding.
- Land Phase-0 hardening that is independent of storage: `esc()` on all user/external fields entering the DOM (app.js:3276, 4403, 4417–4427; profiles.js:89,151); remove default password `1234` (per-account random + forced reset; seed demo accounts flagged demo-only); Edge Functions fail-closed on missing webhook secret + CORS restricted to trusted origins.
- Write the **failing** job-domain test skeleton (unit + RLS/RPC + e2e) so later stages turn them green.
- **No storage/authority change yet.**

### Stage 1 — Relational job schema, RLS & RPC contract
- Confirm/extend `jobs`, `job_close_pins`, `job_timeline`, `job_attachments` and the minimal room/assignee relationship needed for authorization.
- Define the RPC **contract** (signatures, inputs, outputs, error codes) for `create_job`, `assign_job`, `update_job_status`, `verify_job_completion`, plus a read RPC/view `list_jobs_for_current_user`.
- Define the internal shared function `_create_job_internal(...)` and the transactional `ingest_google_form_submission(...)` boundary (Amendment 1).
- Define `import_legacy_job` contract (see §4).
- RLS: jobs readable only via `can_read_job`; writes only via SECURITY DEFINER RPC; anonymous/direct table insert rejected.
- **No frontend wiring yet.**

### Stage 2 — Server-enforced workflow
- Inside RPCs: PIN validation on completion or force `pending_inspection` + `waiting_owner_or_admin_verification`; required-evidence checks; legal status-transition table; server-side input sanitization; write `job_timeline` **and** `audit_logs` on every transition; Asia/Bangkok date normalization server-side.
- Fix `get_app_bootstrap` so jobs are **never** served from `app_snapshots` (always relational).
- Implement the transactional body of `ingest_google_form_submission` (Amendment 1): one transaction covering idempotency, submission row, exactly one job, initial timeline, audit, retry-returns-existing, full rollback on failure; Edge Function cannot set actor/assignee/completed/verifier/admin fields. Keep the Form **trigger disabled** until Stage 7.
- Tests: RLS/RPC suite (AT-4,5,7,8,10,12) green on staging.

### Stage 3 — Frontend relational read path
- On `JOB_BACKEND=supabase`, hydrate the `jobs` cache exclusively from `list_jobs_for_current_user`.
- Remove `jobs` from `remoteSnapshot()` (app.js:1515) and its application in `applyBackendSnapshot()` (app.js:1616) / `loadRemoteSnapshot()` (app.js:1546).
- **All external Supabase job writers remain disabled.** This stage proves reads work in isolation.

### Stage 4 — Frontend record-level write path
- Repoint `createJob/assignJob/updateJobStatus/verifyCompletion` to the RPCs, **preserving their signatures** so render code is untouched; after each RPC, refresh the cache from the read RPC.
- WebApp job writes now go through RPC only (still staging).

### Stage 5 — Legacy import & reconciliation
- Implement `import_legacy_job` (§4). Run **dry-run** first; then import fake/approved staging data; reconcile counts, ids, statuses, relationships.

### Stage 6 — Disable snapshot & localStorage job authority
- Hard-off (behind flag / removed after tests): `saveJobs()` localStorage writes except demo; legacy Apps Script job sync (`remoteRequest`/`queueRemoteSync` for jobs, app.js:1530–1588); any snapshot job path.
- After this stage, with `JOB_BACKEND=supabase`, no localStorage/snapshot job authority exists.

### Stage 7 — Google Form direct ingestion
- Enable the Form Apps Script trigger → Edge Function → **`ingest_google_form_submission`** transactional RPC (Amendment 1), idempotent by `external_id`. Only after Stages 0–6 pass.

### Stage 8 — End-to-end verification & cutover package
- Full DoD (§6) on staging with fake data; produce cutover runbook, rollback runbook, tagged release, migration-down script, reconciliation report.

## 3a. Mandatory Amendments (approved after first plan)

### Amendment 1 — Transactional Google Form ingestion
Google Form intake must **not** be an Edge Function that separately writes `google_form_submissions` and then calls the public `create_job` RPC. Instead use a dedicated transactional DB boundary **`ingest_google_form_submission(...)`**. The Edge Function authenticates + validates the webhook, then calls this ingestion RPC **once**. Within **one transaction** it must:
1. Enforce idempotency via `external_id`.
2. Insert or identify the `google_form_submissions` row.
3. Create exactly one `jobs` row.
4. Create the initial `job_timeline` event.
5. Create the `audit_logs` event.
6. Return the existing job on idempotent retry.
7. Roll back everything if any required step fails.

To avoid duplicating rules, `create_job` and `ingest_google_form_submission` may share the same **private/internal** normalized-job-creation function. However:
- the Edge Function must **not** choose arbitrary actor identity, assignee, completed status, verifier, internal permissions, or admin fields;
- service-role access stays **inside** the Edge Function;
- direct anonymous table inserts remain rejected;
- external submission / job / timeline / audit records must never be left partially completed.

Affects Stages 1 (define `ingest_google_form_submission` + internal `_create_job_internal`), 2 (implement transactional body + enforcement), 7 (activate the trigger against this RPC only).

### Amendment 2 — Test suite must remain green
Stage 0 must not leave the suite failing. Behavior that cannot pass until a later stage is declared with an explicit **pending** marker (`test.todo` / `test.skip` / framework-native), each naming the activating stage (Stage 1 RLS & direct-insert rejection; Stage 2 server PIN/evidence/transition; Stage 3 relational reads; Stage 4 record-level writes; Stage 7 Form e2e). All Stage-0-implemented behavior must **pass**: HTML escaping/safe rendering, malicious profile/job names inert, password generation, demo-account isolation, webhook missing-secret fail-closed, CORS behavior, static JS checks, Edge Function type checks. Every gate distinguishes **passing active / pending-by-stage / genuinely failing**. No genuinely failing test may be excused by staging.

### Amendment 3 — Legacy PIN migration (applies to Stage 5 / §4)
Legacy job PIN must never be preserved or imported as plaintext:
1. Plaintext PIN must never be written to `jobs`, `jobs.payload`, `job_timeline`, `audit_logs`, import reports, or application logs.
2. If a legacy PIN must remain usable: transmit only through the protected import RPC; hash immediately **inside the database** using the approved password/PIN hashing (bcrypt via `crypt`/`gen_salt`); discard plaintext after processing.
3. If a legacy PIN's quality/origin/integrity is unverifiable: rotate it, create a new secure PIN, record only that rotation occurred.
4. Import results may report only: `pin_migrated` / `pin_rotated` / `no_pin` / `pin_migration_failed`.
5. Never return a PIN or PIN hash in the import result.
6. Dry-run validates PIN-migration feasibility without exposing or persisting the PIN.

## 4. Data-Import Specification

**[REC] Do NOT use `create_job` for legacy import.** `create_job` generates new ids/timestamps/PINs and is designed for fresh intake; it cannot preserve historical identity or provenance and is not idempotent across re-runs for existing records.

Use a dedicated, access-restricted **`import_legacy_job` RPC** (admin/service-role only), driven by a version-controlled migration script.

**Must preserve (verbatim from source):**
original job identifier · original `created_at`/`updated_at` · current status & sub-status · assignee & assigner relationships · original evidence references · timeline history · completion state · PIN-related state (hash, rotation) · source/provenance · idempotency across repeated attempts.

**Must support:**
- **Dry-run mode** — validate + report, write nothing.
- `import_batch_id` — groups one import run.
- `legacy_id` — the original job id, stored on the row.
- `source = 'legacy_local_storage'` — provenance tag.
- **Database-level uniqueness** — unique on (`source`, `legacy_id`) so re-running cannot duplicate.
- **Per-record failure reporting** — return `{legacy_id, status: ok|skipped|failed, reason}` per record.
- **Count reconciliation** — return `{submitted, inserted, skipped_existing, failed}`.
- **Safe re-running** — idempotent: existing (`source`,`legacy_id`) → skipped, not re-inserted or mutated.
- **No user-notification side effects** — no LINE/toast/email; audit-only.

**Import row shape (target):** map legacy job → relational `jobs` with `id = legacy_id` (or a deterministic derived id if legacy ids collide with the new scheme — decided in Stage 1), preserving timestamps and status; PIN state → `job_close_pins`; timeline → `job_timeline` (marked `imported=true`); evidence refs → `job_attachments`.

**Legacy PIN handling (Amendment 3 — binding):**
- Plaintext PIN is never written to `jobs`, `jobs.payload`, `job_timeline`, `audit_logs`, import reports, or app logs.
- A usable legacy PIN is transmitted only through `import_legacy_job`, hashed immediately in-DB via `crypt(pin, gen_salt('bf'))` into `job_close_pins`, then the plaintext is discarded.
- Unverifiable PIN → rotate to a new secure PIN; record only that rotation happened.
- Per-record PIN outcome is one of: `pin_migrated` / `pin_rotated` / `no_pin` / `pin_migration_failed`.
- The import result never returns a PIN or PIN hash.
- Dry-run validates PIN-migration feasibility without exposing or persisting the PIN.

**Reconciliation gate:** import is accepted only when `inserted + skipped_existing = submitted` and `failed = 0` (or failures explicitly reviewed/approved).

## 5. Cutover & Rollback Specification

### 5.1 Cutover order (binding — read path before any writer)
1. Create & validate Supabase **staging**.
2. Implement relational job schema, RPCs, RLS, workflow enforcement.
3. Implement frontend Supabase **read** path.
4. Test reads while **all external Supabase job writers remain disabled.**
5. Run legacy import in **dry-run**.
6. Import fake/approved staging data.
7. Reconcile counts, ids, statuses, relationships.
8. **Disable every legacy job writer and snapshot job path.**
9. Enable WebApp job writes **through RPC only.**
10. Verify create, assign, update, PIN completion, no-PIN fallback, verification, audit history.
11. Enable Google Form direct ingestion **only after** the preceding steps pass.

**Invariant:** no Supabase job writer is active before Step 3 (read path) is complete and verified. At no moment are two systems accepting job writes.

### 5.2 Rollback (must not reintroduce two sources of truth)
**Normal application rollback = move backward along the single-authority axis; Supabase stays the sole job authority.**
- Redeploy the previous **Supabase-reading** frontend.
- Redeploy the previous RPC / Edge Function version.
- Disable the Google Form trigger if the fault is in intake.
- **Keep Supabase as the only job authority.** Do **not** re-enable localStorage or snapshot as authoritative.

**Database restore is reserved** for confirmed database corruption or a destructive migration failure — **not** ordinary application rollback. A restore uses Supabase point-in-time/backup to a known-good state, after which the prior Supabase-reading frontend is redeployed.

**Pre-cutover rollback** (Stages 0–7, staging only) is trivial: redeploy prior demo build; no divergence exists because Supabase job writes were never enabled outside staging.

## 6. Expanded Definition of Done

The job domain is **not half-migrated** only when **all** pass, proven by automated tests where possible:

1. With `app_snapshots` populated, relational jobs still appear correctly in the WebApp.
2. A Google Form job appears in the WebApp.
3. A WebApp-created job appears after reload in a **different browser session**.
4. A localStorage job modification **cannot** change the authoritative job.
5. A snapshot save **cannot** overwrite a relational job.
6. Duplicate `external_id` creates **exactly one** job.
7. Direct anonymous insert into `jobs` is **rejected**.
8. Unauthorized users **cannot** read or update unrelated jobs.
9. An assignee **cannot** bypass the PIN or completion workflow.
10. No-PIN completion becomes `pending_inspection` (+ `waiting_owner_or_admin_verification`).
11. Authorized verification completes the job.
12. Every transition creates **immutable** `job_timeline` and `audit_logs` records.
13. Asia/Bangkok job dates are correct (no UTC off-by-one), including near-midnight boundary.
14. Disabling the Form trigger stops new external intake **without affecting existing jobs.**
15. Legacy job sync (localStorage/snapshot/Apps Script) remains **hard-disabled** after cutover (grep proves the paths are unreachable outside demo).

## 7. Stage Gate Protocol

After **every** stage, implementation stops and returns:
- **Files changed** (list).
- **Migration changes** (SQL added/modified).
- **Tests run** (commands) and **actual results** (pass/fail counts, output).
- **Unresolved failures** (if any).
- **Git diff summary.**
- **Rollback point** (how to revert this stage safely).
- **Approval question** (explicit go/no-go for the next stage).

**No later stage may begin automatically.** Legacy job write code is not removed until Stages 4–7 pass on staging.

---

## 8. Final Opus Implementation Prompt

> **Role & guardrails.** You are implementing the job-domain rebuild described in `docs/audit/14-strategy-b-rebuild-plan.md`. Do **not** change UI, CSS, DOM structure, or Thai/English labels. Do **not** add PM/LINE/Push/Calendar/finance/multi-tenant. Do **not** modularize `app.js` for style; extract a job API/workflow seam only where functionally required to route writes through RPC. Work against a **staging** Supabase project with **fake data**. Never touch production or production data. There is **no dual-write mode**: the build is either `JOB_BACKEND=supabase` or `JOB_BACKEND=demo-local`.
>
> **Single-authority rule.** Enforce §1 exactly. When `supabase`: job reads only from Supabase; writes only via approved RPCs/Edge Functions; localStorage/snapshot/Apps Script jobs ignored and unwritten; Google Sheet archive-only. When `demo-local`: Supabase job writes and Form ingestion disabled; UI shows a visible "DEMO" badge; no real resident data.
>
> **Work stage by stage (Stage 0 → 8, §3). Stop after each stage and return the §7 gate report. Do not start the next stage until I approve.**
>
> - **Stage 0:** tooling (`package.json`, `.gitignore`, ESLint, `deno check`, Vitest, Playwright); storage-independent hardening (escape all user/external fields entering the DOM — app.js:3276,4403,4417–4427 and profiles.js:89,151; remove default password `1234` → per-account random + forced reset, seed demo accounts flagged demo-only; Edge Functions fail-closed on missing webhook secret; CORS restricted). Add failing job-domain test skeleton. No authority change.
> - **Stage 1:** relational schema/RLS + RPC contracts (`create_job`, `assign_job`, `update_job_status`, `verify_job_completion`, read `list_jobs_for_current_user`, `import_legacy_job`); anonymous/direct insert rejected. No frontend wiring.
> - **Stage 2:** server-enforced workflow in RPCs (PIN or pending-inspection fallback; required evidence; legal transitions; sanitize; write `job_timeline`+`audit_logs`; Asia/Bangkok dates). Fix `get_app_bootstrap` to never serve jobs from `app_snapshots`. Implement the transactional `ingest_google_form_submission` (Amendment 1: one transaction, idempotent, exactly one job + timeline + audit, rollback on failure, Edge Function cannot set actor/assignee/completed/verifier/admin); keep the Form trigger disabled.
> - **Stage 3:** frontend relational **read** path; hydrate `jobs` cache from `list_jobs_for_current_user`; remove `jobs` from `remoteSnapshot()`/`applyBackendSnapshot()`/`loadRemoteSnapshot()`. All Supabase job writers stay disabled.
> - **Stage 4:** repoint `createJob/assignJob/updateJobStatus/verifyCompletion` to RPCs, preserving signatures; refresh cache after each write.
> - **Stage 5:** `import_legacy_job` per §4 — dry-run first, then staging import, then reconciliation report. Legacy PIN never stored/returned as plaintext (Amendment 3): hash in-DB or rotate; report only `pin_migrated`/`pin_rotated`/`no_pin`/`pin_migration_failed`.
> - **Stage 6:** hard-disable localStorage/snapshot/Apps Script job authority (behind flag or removed after tests).
> - **Stage 7:** enable Google Form Apps Script trigger → Edge Function → `ingest_google_form_submission` transactional RPC (Amendment 1), idempotent by `external_id`.
> - **Stage 8:** run the full Definition of Done (§6) on staging; produce cutover runbook, rollback runbook (§5 — never localStorage/snapshot authority; DB restore only for corruption), tagged release, migration-down script, reconciliation report.
>
> **Data import (§4):** never use `create_job` for legacy import; use `import_legacy_job` preserving ids/timestamps/status/relationships/evidence/timeline/completion/PIN/provenance; support dry-run, `import_batch_id`, `legacy_id`, `source='legacy_local_storage'`, DB uniqueness on (source, legacy_id), per-record failure reporting, count reconciliation, safe re-run, no notification side effects.
>
> **Cutover (§5.1):** read path before any writer; disable legacy writers (Step 8) before enabling RPC writes (Step 9); Form ingestion last (Step 11).
>
> **Definition of Done:** all 15 checks in §6 pass with tests where possible. Stop and report at every gate.

---

## Assumptions & residual risk
- **[ASSUMPTION]** A staging Supabase project will be provisioned before Stage 1; production untouched throughout.
- **[ASSUMPTION]** Legacy job volume is small (README ~30 users), so import is cheap and a one-time dry-run + import is sufficient.
- **[RISK]** Legacy job ids may collide with the new `JC-…`/`GF-…` scheme; resolved in Stage 1 by choosing `id = legacy_id` with a deterministic prefix if needed, recorded via `legacy_id` + `source`.
- **[RISK]** Non-job domains (resident PII, team) still ride the snapshot bridge after this phase; acceptable **only** once `jobs` is removed from the snapshot payload; they are the next migration target.
- **[FACT/limit]** Not runtime-verified against a live Supabase instance yet; the `get_app_bootstrap` snapshot-preference finding (migration:437–458) is unambiguous in code and must be re-confirmed once staging exists.
