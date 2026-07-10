# STAGE 1 GATE REPORT — Relational job schema, RLS & RPC contract

> Date: 2026-07-10 · Branch: `feat/stage-1-job-domain-schema` · Baseline: Stage 0
> commit `6b2e42d` (tag `stage-0-approved`). Per the stage-gate protocol in
> `docs/audit/14-strategy-b-rebuild-plan.md` §7. **Hard stop — Stage 2 not started.**

## 1. Files changed

New files (additive; no existing file modified):

| File | Purpose |
| --- | --- |
| `supabase/migrations/202607100001_job_domain_stage1.sql` | Stage 1 migration (schema, privileges, RLS, RPC contract) |
| `docs/audit/15-job-domain-rpc-contract.md` | Frozen RPC contract (signatures, I/O, error codes, availability) |
| `supabase/tests/stage1_smoke.sql` | Structural smoke assertions to run on staging with psql |
| `docs/audit/STAGE-1-GATE-REPORT.md` | This report |

Explicitly untouched (per plan): `get_app_bootstrap`, `save_client_snapshot`,
`remoteSnapshot`/`applyBackendSnapshot`, localStorage job behavior, all
frontend job reads/writes, `SUPABASE_ENABLED`, the Google Form trigger, all
Edge Functions, UI/CSS/DOM.

## 2. Migration changes (`202607100001_job_domain_stage1.sql`)

1. **Provenance/workflow columns (additive):** `jobs.legacy_id`,
   `jobs.import_batch_id`, `jobs.raw` (**boolean triage flag**,
   `not null default false` — `true` = untriaged external-intake job awaiting
   staff classification; **not** a raw JSON payload, which stays in
   `google_form_submissions.payload`), `jobs.completed_at` (server-set in
   Stage 2), `job_timeline.imported`; partial unique index
   `uq_jobs_source_legacy` on `(source, legacy_id) where legacy_id is not
   null` (idempotent re-import); supporting indexes on `import_batch_id`,
   `job_attachments(job_id)`, and the raw-intake triage-pool index
   `idx_jobs_raw_open` on `(created_at desc) where raw = true and
   status = 'open'` (the earlier general `idx_jobs_open` was removed; no
   documented need for a general open-job index exists).
2. **Privilege boundary:** INSERT/UPDATE/DELETE (and TRUNCATE/REFERENCES/
   TRIGGER) revoked from `anon` and `authenticated` on `jobs`, `job_timeline`,
   `job_attachments`; **all** privileges revoked on `job_close_pins` and
   `google_form_submissions`; `anon` SELECT revoked on all job tables.
3. **RLS:** loose v1 `jobs_insert`/`jobs_update` policies dropped (SEC-09);
   new `job_timeline_select` and `job_attachments_select` authorize reads
   through `can_read_job(job_id)`; `job_close_pins` and
   `google_form_submissions` have no policy → deny by default.
4. **Read RPC:** `list_jobs_for_current_user()` (live) — payload merged with
   the **complete** set of authoritative relational columns (including `raw`),
   which always override stale payload keys **including when the relational
   value is NULL** (no `jsonb_strip_nulls`; a relational NULL removes the
   authority of a stale payload value); filtered by `can_read_job`, no PIN
   material.
5. **Write-RPC contract, fail-closed:** the v1 bodies of `create_job`,
   `assign_job`, `update_job_status`, `verify_job_completion` — which allowed
   completion without PIN/evidence/transition checks (F-04, F-09) — are
   replaced by stubs raising `JOB_WRITES_UNAVAILABLE`. New contract stubs:
   `_create_job_internal` (`INTERNAL_ONLY`; EXECUTE revoked from **all**
   roles including service_role — reachable only from the definer context of
   its two entry points), `ingest_google_form_submission`
   (`INGESTION_UNAVAILABLE`, service-role only, Amendment 1),
   `import_legacy_job` (authorized for admin accounts **or** service-role
   callers via `auth.role()`; others get `FORBIDDEN`, authorized callers get
   `IMPORT_UNAVAILABLE`; Stage 5, Amendment 3). **No partial insecure write
   path exists.**
6. All functions are `SECURITY DEFINER` with `set search_path = public`;
   EXECUTE revoked from `PUBLIC`/`anon`, granted explicitly.

## 3. RPC contract summary

See `docs/audit/15-job-domain-rpc-contract.md`. Live in Stage 1:
`list_jobs_for_current_user()` only. Stage 2 implements the enforced bodies
(PIN or forced `pending_inspection`+`waiting_owner_or_admin_verification`,
evidence rules, legal transition table, `job_timeline`+`audit_logs` on every
transition, Asia/Bangkok dates, transactional ingestion). Stage 5 implements
`import_legacy_job` (dry-run, per-record report, reconciliation, in-DB PIN
hash/rotate; plaintext never persisted or returned). Shared error vocabulary
defined (`AUTH_REQUIRED`, `FORBIDDEN`, `PIN_INVALID`, `EVIDENCE_REQUIRED`,
`ILLEGAL_TRANSITION`, `DUPLICATE_SUBMISSION`, `INVALID_INPUT`, …).

## 4. RLS & privilege summary

| Table | anon | authenticated | Writes |
| --- | --- | --- | --- |
| `jobs` | none | SELECT via `can_read_job` | RPC only (denied at privilege + no policy) |
| `job_timeline` | none | SELECT via `can_read_job(job_id)` | RPC only |
| `job_attachments` | none | SELECT via `can_read_job(job_id)` | RPC only |
| `job_close_pins` | none | **none** | RPC-internal only |
| `google_form_submissions` | none | none | service-role ingestion boundary only |

Service role (Edge Functions) is unaffected, as designed; the Form trigger
remains disabled and the existing Edge Functions were not modified or deployed.

## 5. Commands run and actual results

| Command | Result |
| --- | --- |
| `npm run check` | **PASS** — all 5 JS files pass `node --check` |
| `npm test` | **PASS** — 35 tests: 14 pass, 0 fail, 21 todo (pending-by-stage per Amendment 2) |
| `git diff --check` | clean (no whitespace/conflict markers) |
| `git status` | clean tree + 3 new untracked deliverables (this report makes 4) |
| Structural SQL validation (node script) | dollar-quoting balanced (16 & 16 `$$` tokens), parentheses balanced (0 delta), 0 psql meta-commands, in both SQL files |
| `psql` / `docker` / `supabase` CLI | **not available locally** — no database execution attempted |

## 6. Tests — passing / pending / failing

- **Passing (14):** all Stage 0 active tests (escaping/XSS inertness, password
  policy, demo isolation, webhook fail-closed/CORS, script ordering).
- **Pending by stage (21 `todo`):** unchanged from Stage 0, including the four
  Stage 1 markers (direct-insert rejection, BOLA read, `list_jobs_for_current_user`
  filtering, `import_legacy_job` contract). They require a live database and
  remain `todo` until the migration is applied to the existing staging
  project; the corresponding assertions are encoded
  in `supabase/tests/stage1_smoke.sql`, which is plain SQL (no psql
  meta-commands) so it runs unchanged in the Supabase SQL Editor or via psql.
- **Genuinely failing: 0.**

## 7. Not runtime-verified (declared limits)

- The Stage 1 migration has **not** been applied to any database; no
  PostgreSQL parsed or executed it. Validation was structural only.
- `supabase/tests/stage1_smoke.sql` has **not** been executed.
- RLS/privilege behavior (deny direct writes, pin unreadability, BOLA) is
  therefore asserted by design + smoke script, not yet observed live.
- A Supabase staging project **exists**, but this migration has **not yet
  been applied** to it and the smoke test has not yet been run against
  PostgreSQL; runtime verification is still pending.

## 8. Git diff summary

Working tree vs `stage-0-approved` baseline — 4 new files, 0 modified, 0 deleted:

```
docs/audit/15-job-domain-rpc-contract.md           | 180 lines (new)
supabase/migrations/202607100001_job_domain_stage1.sql | 287 lines (new)
supabase/tests/stage1_smoke.sql                    | 198 lines (new)
docs/audit/STAGE-1-GATE-REPORT.md                  | (this file, new)
```

## 9. Rollback point

Nothing has been applied anywhere, so rollback is purely local:

- Uncommitted: `git clean -fd supabase/tests && git checkout -- .` (or delete
  the four files) restores the exact Stage 0 tree.
- After commit: `git revert <stage-1-commit>` or reset the branch to
  `stage-0-approved`.
- If the migration is later applied to staging and must be undone: restore
  the staging DB or run a down script (drop the two jobs columns + indexes,
  `job_timeline.imported`, the three new functions; re-run migration
  `202607090001` to restore the v1 RPC bodies, policies and grants). No
  production database is involved at any point.

## 10. Confirmation — no Supabase resource modified

No migration was applied, no `supabase db push`, no `psql`/CLI connection was
made (none is installed), no Edge Function was deployed or edited, no secret
was requested or handled, and no production or staging Supabase project was
touched in any way. All Stage 1 output is files in this repository.

## 11. Approval request

**Go/no-go:** approve applying migration `202607100001_job_domain_stage1.sql`
to a **staging** Supabase project (with fake data only) and running
`supabase/tests/stage1_smoke.sql` there to runtime-verify the Stage 1
boundary — after which Stage 2 (server-enforced workflow) can be authorized.
Stage 2 will not begin without explicit approval.
