# STAGE 5 GATE REPORT — Legacy import & reconciliation

> Date: 2026-07-11 · Branch: `feat/stage-5-legacy-import` · Baseline: Stage 4
> closed and tagged `stage-4-staging-verified` (commit `866e4d2`). Per the
> stage-gate protocol in `docs/audit/14-strategy-b-rebuild-plan.md` §7.
> **Hard stop — Stage 6 not started. The Stage 5 migration has NOT been
> applied. No dry-run or import has been executed. No credential used.
> `SUPABASE_ENABLED` remains false. Form trigger disabled.**

## 1. What Stage 5 delivers

The enforced body of `import_legacy_job(p_import_batch_id, p_job, p_dry_run)`
(signature, grants and admin/service-role authorization unchanged from the
frozen Stage 1 contract), plus its operational tooling: a staging-only
driving script, a fake sample dataset, a version-controlled cleanup script,
staging smoke assertions, and local guards. `create_job` is never used for
import (test-enforced).

## 2. Deterministic target id

`jobs.id = 'LG-' || upper(first 12 hex of sha256(lower(trim(source)) || ':' || trim(legacy_id)))`
— namespaced, no randomness, order-independent; the same source+legacy_id
always yields the same id and different sources with the same legacy_id
diverge. `source` and `legacy_id` are preserved verbatim in their dedicated
columns; `uq_jobs_source_legacy` remains the idempotency authority
(re-import → `skipped / already_imported`, zero mutation). A theoretical
hash collision surfaces as `failed / TARGET_ID_COLLISION` (rolled back),
never a silent overwrite.

## 3. Transaction & rollback

One RPC call = one record = one transaction. All validation (batch id,
legacy id, status/sub-status mapping, timestamp ordering, evidence
classification, relationship resolution) happens before any write; the write
phase (job row → rotated PIN → provenance timeline → stable attachments →
audit) sits in a nested plpgsql block whose exception handler discards every
write and returns a safe `failed` result. No partial record can persist.
Batch reconciliation lives outside the per-record transactions, in the
driver.

## 4. Dry-run

`p_dry_run = true` (the default) returns validation + reconciliation
information (`target_id`, notes, pin outcome) and writes **nothing**: no
jobs, job_close_pins, job_timeline, job_attachments, audit_logs, Storage
objects or notification records. The smoke test proves zero row-count delta
across all five tables.

## 5. PIN policy (rotate-all, Amendment 3)

localStorage-origin plaintext PINs are never trusted or preserved. An active
job with a legacy PIN gets a fresh PIN generated **inside the database**
(pgcrypto randomness), stored only as `extensions.crypt(pin, gen_salt('bf'))`
with `rotated_at = now()`; the plaintext variable is nulled immediately.
Terminal jobs or absent PINs → `no_pin`; hash failure → record fails with
`pin_migration_failed`. Neither the old nor the new plaintext, nor any hash,
ever appears in results, payloads, timeline, audit rows, or logs
(smoke + local guards). Report vocabulary is exactly
`pin_migrated | pin_rotated | no_pin | pin_migration_failed`
(`pin_migrated` reserved for a future trusted source).

**Operational consequence (documented):** Stage 5 does not distribute the
rotated PIN. Before relying on PIN completion for an imported job, an
approved PIN re-issue flow (or the existing no-PIN → admin-verification
path) is required. No frontend PIN-reissue feature is added in Stage 5.

## 6. Evidence policy (fail-closed)

Stable managed references (`objectPath`, path-shaped, no embedded data) map
to real `job_attachments` rows linked to the imported job. Embedded
dataURL/base64/blob/local-file evidence — or any attachment object without a
managed reference — fails the **whole record** with
`EVIDENCE_BINARY_MIGRATION_REQUIRED`: dry-run reports it writing nothing; a
real import rolls the record back entirely. No metadata-only attachment rows
are created; no Storage upload occurs anywhere in Stage 5.

**Future ticket — binary evidence migration:** checksum verification of each
object, upload + reconciliation pass, compensation/cleanup on partial
failure, and only then attachment-row creation; until it lands, records with
embedded evidence legitimately fail the gate and need explicit review.

## 7. Timeline, timestamps, relationships

Legacy timeline entries are preserved as `job_timeline` rows with
`imported = true` and their original `created_at` (naive timestamps read as
Asia/Bangkok); nothing historical is fabricated — a record without timeline
imports with zero timeline rows. `created_at`/`updated_at`/`completed_at`
are preserved verbatim; impossible orderings fail
(`INVALID_TIMESTAMP_ORDER`). Unknown statuses/sub-statuses fail
(`INVALID_STATUS` / `INVALID_SUB_STATUS`) — never coerced. Unresolved
reporter/assignee/assigner/room references import as relational NULLs with
`unresolved_*` notes in the reason and payload; users/rooms are never
invented. `DEL-*` / `deleteRequest` pseudo-jobs are excluded
(`skipped / pseudo_job`).

## 8. Reconciliation

Per-record result: `{legacy_id, status: ok|skipped|failed, reason,
pin_outcome}` — never PIN material, passwords, JWTs, tokens, keys, private
evidence URLs or raw payload content. The driver computes
`{submitted, inserted, skipped_existing, failed}` with failures grouped by
reason and listed individually. Acceptance gate:
`inserted + skipped_existing = submitted` **and** `failed = 0`. An
`EVIDENCE_BINARY_MIGRATION_REQUIRED` failure counts as failed and blocks
acceptance unless explicitly reviewed and separately approved. Note: the
fake sample intentionally contains one such record, so a full-sample run is
**expected** to gate FAIL pending that review — by design.

## 9. Driver security (`scripts/import-legacy-jobs.mjs`)

Credential is the **modern Supabase Secret Key** read only from the
`SUPABASE_SECRET_KEY` environment variable, strictly validated against
`^sb_secret_[A-Za-z0-9_-]{10,}$` — empty values, publishable/anon/legacy-JWT
keys, masked display copies (asterisks/bullets/ellipsis), whitespace, line
breaks, non-printables and arbitrary text are rejected with only the generic
message "Invalid server credential format" (the value is never echoed,
partially displayed, hashed, or included in errors). The key is sent **only**
in the `apikey` request header; no `Authorization: Bearer` header exists in
the driver (that pattern is the deprecated legacy service_role-JWT flow,
found unusable during the first Section D attempt — the credential-format
precheck failed before any request reached Supabase, and no import
occurred). Credential-shaped argv values are refused outright; the key never
appears in stdout/stderr/reports (guarded per console line by tests).
Project allowlist contains exactly the staging ref `wdqadjikpkclmihbnfgg`;
every other ref is refused. Dry-run is the default; a real write requires
both `--commit` and `CONFIRM_IMPORT=<exact --batch uuid>`. One RPC call per
record; the only network call is the import RPC.

## 10. Cleanup (`supabase/tests/stage5_cleanup.sql`)

Version-controlled, staging-only, inert until an administrator fills in the
exact `import_batch_id` and the confirmation value `CLEANUP-<batch-id>`.
Single transaction: previews counts (jobs/pins/timeline/attachments),
verifies every targeted job is legacy-sourced and of the exact batch, aborts
on any mismatch — including non-imported (live) timeline rows, which force
manual review — deletes only that batch, re-verifies, and records one safe
audit row (ids + counts only). **Import audit rows are deliberately
retained:** `audit_logs` is the immutable history; cleanup is recorded as a
compensating event, never an eraser. Not executed in this phase.

## 11. Fake sample (`scripts/legacy-sample-jobs.json`)

Eleven records, all explicitly fake (no real names/rooms/phones/emails/
images): normal record · alias status (`follow_up`) · unresolved
relationships · completed no-PIN · active plaintext-PIN (→ `pin_rotated`) ·
stable objectPath evidence · embedded dataURL evidence (must fail) ·
`DEL-*` pseudo-job (must be excluded) · the same `legacy_id` under two
sources (id divergence) · a repeated record (idempotency).

## 12. Files changed (exactly the nine approved)

`supabase/migrations/202607110001_import_legacy_job_stage5.sql` (new; version
verified unique) · `supabase/tests/stage5_smoke.sql` (new; writes wrapped in
BEGIN/ROLLBACK; service-role simulated via transaction-local JWT claims — no
credential) · `supabase/tests/stage5_cleanup.sql` (new) ·
`scripts/import-legacy-jobs.mjs` (new) · `scripts/legacy-sample-jobs.json`
(new) · `test/stage5-import.test.js` (new, 12 active guards) ·
`test/pending-future-stages.test.js` (2 Stage 5 TODOs converted) ·
`docs/audit/STAGE-5-GATE-REPORT.md` (new) ·
`docs/audit/15-job-domain-rpc-contract.md` (§8 updated).

Untouched: all frontend files, `config.js`, Edge Functions, Form ingestion,
every applied migration, Production.

## 13. Tests

`npm test`: **63 tests — 48 pass, 0 fail, 15 todo** (was 53: 36/0/17).
Twelve new active Stage 5 guards; both Stage 5 TODOs converted (duplicate
source+legacy_id idempotency; rotate-all PIN never stored/returned
plaintext). Remaining 15 TODOs: Stage 1/2 live-DB markers, Stage 4
cross-session reload, Stage 7.

## 14. Not runtime-verified (declared limits)

Migration `202607110001` has not been applied to any database; the smoke
test, driver, dry-run, real import, and cleanup have not been executed.
PIN rotation, per-record rollback, dry-run zero-write and idempotency are
asserted structurally and by the (unexecuted) smoke script until the staging
dry-run is approved.

## 15. Rollback point

Nothing applied or executed anywhere. `git checkout stage-4-staging-verified
-- .` (or revert the Stage 5 commit once created) restores the verified
Stage 4 tree. Post-apply staging rollback = the reviewed cleanup script
(§10) plus, if the function itself must go, re-running migration
`202607100001` §5 to restore the Stage 1 fail-closed stub.

## 16. Approval request

**Go/no-go:** (1) approve one commit of the nine Stage 5 files and push;
(2) approve the staging sequence — apply `202607110001`, run
`stage5_smoke.sql` (rolled back), then a driver **dry-run** over the fake
sample; the real fake-sample import happens only after you review the
dry-run output (including the one intentional evidence failure) and approve
separately. Stage 6 does not begin without explicit approval.
