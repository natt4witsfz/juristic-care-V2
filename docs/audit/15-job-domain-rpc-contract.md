# 15 — Job Domain RPC Contract (Stage 1)

> Status: **contract defined, bodies fail-closed.** Established by migration
> `supabase/migrations/202607100001_job_domain_stage1.sql` per
> `docs/audit/14-strategy-b-rebuild-plan.md` §3 Stage 1 and Amendment 1.
> Signatures below are frozen; Stage 2 (workflow) and Stage 5 (import) supply
> the enforced bodies without changing them. All functions are
> `SECURITY DEFINER` with `set search_path = public` and explicit grants
> (`EXECUTE` revoked from `PUBLIC` and `anon`).

## Availability matrix

| Function | Callable by | Stage 1 behavior | Implemented in |
| --- | --- | --- | --- |
| `list_jobs_for_current_user()` | authenticated, service_role | **Live** — returns permitted jobs | Stage 1 |
| `create_job(jsonb)` | authenticated, service_role | Raises `JOB_WRITES_UNAVAILABLE` | Stage 2 |
| `assign_job(text, uuid, jsonb)` | authenticated, service_role | Raises `JOB_WRITES_UNAVAILABLE` | Stage 2 |
| `update_job_status(text, jsonb)` | authenticated, service_role | Raises `JOB_WRITES_UNAVAILABLE` | Stage 2 |
| `verify_job_completion(text)` | authenticated, service_role | Raises `JOB_WRITES_UNAVAILABLE` | Stage 2 |
| `_create_job_internal(uuid, text, jsonb)` | service_role only (internal) | Raises `INTERNAL_ONLY` | Stage 2 |
| `ingest_google_form_submission(text, jsonb)` | service_role only | Raises `INGESTION_UNAVAILABLE` | Stage 2 (trigger enabled Stage 7) |
| `import_legacy_job(uuid, jsonb, boolean)` | admin via authenticated; service_role | Non-admin → `FORBIDDEN` (42501); admin → `IMPORT_UNAVAILABLE` | Stage 5 |

The v1 write-RPC bodies (which allowed completion without PIN, evidence or
transition checks — findings F-04/F-09) were **removed** in Stage 1 and
replaced by these fail-closed stubs. There is no partial insecure write path.

## Error codes (shared vocabulary)

| Code / message | Meaning |
| --- | --- |
| `AUTH_REQUIRED` | Caller has no active `app_users` row |
| `FORBIDDEN` (errcode 42501) | Caller lacks the role/relationship for this action |
| `JOB_NOT_FOUND` | `p_job_id` does not resolve to a readable job |
| `INVALID_INPUT` | Payload fails validation (missing/oversized/malformed fields) |
| `PIN_INVALID` | Completion PIN does not match `job_close_pins.pin_hash` |
| `EVIDENCE_REQUIRED` | Required photos/reason missing for the target status |
| `ILLEGAL_TRANSITION` | Status change not permitted by the transition table |
| `DUPLICATE_SUBMISSION` | Idempotent retry detected; existing record returned instead where specified |
| `JOB_WRITES_UNAVAILABLE` / `INGESTION_UNAVAILABLE` / `IMPORT_UNAVAILABLE` / `INTERNAL_ONLY` | Stage 1 fail-closed stub reached |

---

## 1. `list_jobs_for_current_user() → setof jsonb` — live

**Auth:** authenticated app user (`current_app_user_id()` non-null); rows
filtered by `can_read_job(job_id)` (admin, `share_public`, assignee, assigner,
reporter, or same room).

**Output:** one jsonb per job: `payload` merged with authoritative columns
`id`, `source`, `status`, `subStatus`, `legacyId`, `createdAt`, `updatedAt`
(columns win over stale payload keys). Ordered `created_at desc`. Never
contains PIN material (`create_job` strips `closePin` before persisting;
`job_close_pins` is unreadable by clients).

**Errors:** none — unauthenticated/unknown callers receive an empty set.

From Stage 3 this is the **only** client job-read path.

## 2. `create_job(p_payload jsonb) → jsonb` — Stage 2

**Purpose:** fresh intake from the authenticated WebApp. Never used for
legacy import (§8).

**Input (`p_payload`):** `title`, `roomNo`/`room`, `mainCategory`, `category`,
`priority`, `jobDate`, `dueDate`, `contactName`, `contactPhone`, `note`,
optional `sharePublic`, optional idempotency key. Server ignores/forbids:
`id` override outside the `JC-` scheme, `status`, `subStatus`, `assignee`,
`assignedBy`, `completedAt`, verifier or permission fields.

**Stage 2 behavior (contract):** delegates to `_create_job_internal` with
`p_actor_id = current_app_user_id()` and `p_source = 'WebApp'`; sanitizes and
validates input server-side; generates the job id (`JC-…`) and a bcrypt-hashed
close PIN in `job_close_pins`; normalizes dates in Asia/Bangkok; writes the
initial `job_timeline` event and an `audit_logs` row in the same transaction.

**Output:** the created job in `list_jobs_for_current_user` shape.
**Errors:** `AUTH_REQUIRED`, `INVALID_INPUT`, `DUPLICATE_SUBMISSION`.

## 3. `assign_job(p_job_id text, p_assignee_id uuid, p_extra jsonb) → jsonb` — Stage 2

**Auth:** admin, or a user with assignment permission over the job
(`can_update_job` + assignment capability); assignee must be an active staff
`app_users` row.

**Stage 2 behavior:** sets assignee/assigned_by, transitions per the legal
transition table (e.g. `open → received`), writes `job_timeline` + `audit_logs`.
**Output:** updated job (read shape).
**Errors:** `AUTH_REQUIRED`, `FORBIDDEN`, `JOB_NOT_FOUND`, `INVALID_INPUT`,
`ILLEGAL_TRANSITION`.

## 4. `update_job_status(p_job_id text, p_payload jsonb) → jsonb` — Stage 2

**Input:** `status` (target), optional `subStatus`, `pin`, `noPinAvailable`,
`reason`, `nextUpdateDate`, evidence references.

**Stage 2 behavior (binding, F-04):**
- Target `completed` **requires** `crypt(pin, pin_hash) = pin_hash` against
  `job_close_pins`; wrong PIN → `PIN_INVALID`, job unchanged.
- `noPinAvailable = true` **forces** `pending_inspection` +
  `waiting_owner_or_admin_verification` and requires a reason and ≥1 photo
  (`EVIDENCE_REQUIRED` otherwise). The RPC never returns `completed` on this
  path.
- Transitions validated against the single legal-transition table
  (`ILLEGAL_TRANSITION`); evidence rules (1–3 photos by status) enforced
  server-side; `nextUpdateDate` is only overwritten when the key is present
  (fixes DB-03); every transition writes `job_timeline` + `audit_logs`.

**Errors:** `AUTH_REQUIRED`, `FORBIDDEN`, `JOB_NOT_FOUND`, `INVALID_INPUT`,
`PIN_INVALID`, `EVIDENCE_REQUIRED`, `ILLEGAL_TRANSITION`.

## 5. `verify_job_completion(p_job_id text) → boolean` — Stage 2

**Auth (restricted, F-04):** admin/co-admin, the assigner, or the reporting
room's owner — **not** the assignee.

**Stage 2 behavior:** valid only when the job is `pending_inspection` with
`waiting_owner_or_admin_verification`; transitions to `completed`, sets
`completedAt` (server time), writes `job_timeline` + `audit_logs`.
**Errors:** `AUTH_REQUIRED`, `FORBIDDEN`, `JOB_NOT_FOUND`, `ILLEGAL_TRANSITION`.

## 6. `_create_job_internal(p_actor_id uuid, p_source text, p_payload jsonb) → jsonb` — Stage 2, internal

Shared normalized creation path used by `create_job` and
`ingest_google_form_submission` so validation, sanitization, id generation,
PIN hashing, timeline and audit live in exactly one place (Amendment 1).
`EXECUTE` is revoked from all client roles; it is reachable only from the
definer context of the two public entry points (and service_role).

## 7. `ingest_google_form_submission(p_external_id text, p_payload jsonb) → jsonb` — Stage 2, service-role only

The single transactional ingestion boundary (Amendment 1). The Edge Function
authenticates and validates the webhook, then calls this **once**. In one
transaction it must: enforce idempotency by `external_id`; insert/identify the
`google_form_submissions` row; create exactly one job via
`_create_job_internal` (source `'GoogleForm'`, no actor identity, no assignee,
no completed/verifier/admin fields); write the initial `job_timeline` and
`audit_logs`; return the existing job on idempotent retry; roll back
everything on failure.

**Output:** `{ job, submission_id, duplicate: boolean }`.
**Errors:** `INVALID_INPUT`; retries with a known `external_id` succeed with
`duplicate: true` rather than erroring. The Form trigger remains disabled
until Stage 7.

## 8. `import_legacy_job(p_import_batch_id uuid, p_job jsonb, p_dry_run boolean default true) → jsonb` — Stage 5, admin/service only

Legacy import per plan §4; `create_job` must never be used for import.

**Input (`p_job`):** `legacy_id` (required), original `created_at`/`updated_at`,
status/subStatus, assignee/assigner references, timeline events, evidence
references, optional legacy PIN (plaintext, in transit only).

**Contract:** provenance `source = 'legacy_local_storage'`, row carries
`legacy_id` + `import_batch_id`; idempotent via the unique index
`uq_jobs_source_legacy` — an existing (`source`,`legacy_id`) is reported
`skipped`, never re-inserted or mutated; timeline rows are marked
`imported = true`; **dry-run writes nothing**. PIN handling (Amendment 3):
hash immediately in-DB via `crypt(pin, gen_salt('bf'))` or rotate; plaintext
is never persisted or logged; outcome reported only as
`pin_migrated | pin_rotated | no_pin | pin_migration_failed`; no PIN or hash
ever appears in the result. No notification side effects.

**Output (per record):** `{ legacy_id, status: ok|skipped|failed, reason,
pin_outcome }`. Batch reconciliation `{submitted, inserted, skipped_existing,
failed}` is accumulated by the driving script; the gate is
`inserted + skipped_existing = submitted` and `failed = 0`.
**Errors:** `FORBIDDEN` (non-admin), `INVALID_INPUT`.

---

## Table-level boundary backing this contract (Stage 1, live)

| Table | anon | authenticated | Notes |
| --- | --- | --- | --- |
| `jobs` | no access | select via `can_read_job` only; **no insert/update/delete** (privilege revoked + policies dropped) | writes only via RPCs above |
| `job_timeline` | no access | select via `can_read_job(job_id)`; no writes | RPCs write it (Stage 2) |
| `job_attachments` | no access | select via `can_read_job(job_id)`; no writes | |
| `job_close_pins` | no access | **no access** (all privileges revoked, no policy) | PIN checks happen inside RPCs only |
| `google_form_submissions` | no access | no access | service-role ingestion boundary only |
