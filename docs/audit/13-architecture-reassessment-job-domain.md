# 13 — Independent Architecture Reassessment: Job Domain Migration

> Reviewer stance: independent Principal Software Architect reviewing a prior plan. No loyalty to the earlier recommendation. Labels: **[FACT]** verified from code, **[RISK]**, **[ASSUMPTION]**, **[REC]** recommendation. No implementation performed. No production touched.

## TL;DR (สรุปสั้น — ภาษาไทย)

คำถามหลัก: *การทำ Google Form → Supabase แบบครึ่งเดียว จะทำให้ระบบอยู่ในสภาพที่อันตรายและขวางการพัฒนามากกว่าการย้าย job domain ทั้งก้อนแบบมีการควบคุมหรือไม่?*

**คำตอบ: ใช่ — อันตรายกว่าอย่างชัดเจน** การเปิดเฉพาะช่องทาง Google Form ให้เขียน Supabase โดยที่ส่วนอื่นยังอยู่บน localStorage/snapshot จะทำให้เกิด **two sources of truth** ทันที และมีหลักฐานในโค้ดที่พิสูจน์ว่า **งานที่เข้า Supabase จะมองไม่เห็นบน frontend** (ดู FACT-1) ดังนั้นแนะนำ **Strategy B (Controlled Core Rebuild ของ job domain เท่านั้น โดยคง UI เดิม)** และให้ Batch 1 เดิม (แก้ XSS/รหัสผ่าน/CORS) **ยังคงอยู่แต่ถูกดูดเข้าเป็น Phase 0 ของ Strategy B** ไม่ใช่ทำแยกแล้วเปิด Form ingestion ก่อน

---

## 1. Direct answer to the core question

**Yes. A partial Google Form → Supabase migration would leave the system in a materially more dangerous and development-blocking state than a controlled end-to-end migration of the job domain.**

The decisive reason is not theoretical — it is provable from the current code.

### FACT-1 (the killer fact): the frontend would not even see the Supabase jobs

`get_app_bootstrap()` (migration `202607090001_full_supabase_schema.sql:437–458`) does this for any staff account:

```
if is_staff_account() then
  select snapshot from app_snapshots order by created_at desc limit 1;
  if snapshot is not null then return snapshot;   -- returns the whole localStorage blob
end if;
-- only if NO snapshot exists does it fall through to relational jobs
```

So the moment **one** `app_snapshots` row exists (written by `save_client_snapshot`, migration:424–435, on every `queueSupabaseSync`), staff clients are served the **snapshot blob**, and the relational `jobs` table — where the Google Form Edge Function writes (`google-forms-ingest/index.ts:61–69`) — is **never read**. A Form-ingested job would sit in `jobs` and be invisible in the UI.

This is not a hypothetical "could drift." It is a guaranteed, immediate divergence. That single fact converts Strategy A from "incremental" into "actively broken."

## 2. Evaluation of each named failure mode under Strategy A (partial)

| Failure mode | Occurs? | Evidence / mechanism |
| --- | --- | --- |
| Two sources of truth | **Yes** | localStorage `jobs` (app.js:672) + relational `jobs` table; both claim authority |
| Two active write paths | **Yes** | `createJob()`→localStorage/snapshot (app.js:1002) vs Edge Function→`jobs` (gf-ingest:61) |
| Jobs in Supabase but not in frontend | **Yes** | FACT-1: `get_app_bootstrap` returns snapshot, ignores relational jobs |
| Stale snapshot overwrites newer DB record | **Yes** | `save_client_snapshot` writes whole blob (migration:424); a client with old data re-saves and buries Form jobs |
| Duplicate / inconsistent jobs | **Yes** | job id schemes differ: `Date.now()`/sequence (app.js:1004) vs `GF-...` (gf-ingest:43); no shared uniqueness |
| Client state disagrees with DB | **Yes** | inevitable once two writers exist with no reconciliation |
| Status changed locally, not server-enforced | **Yes (already true today)** | PIN/evidence/transition only in `validateStatusUpdate` (app.js:1082); RPC `update_job_status` skips them (migration:392) |
| Cannot determine authoritative version | **Yes** | no version/updated_at reconciliation between snapshot and relational rows |
| Future features forced to support both paths | **Yes** | any new job feature must read/write both localStorage and Supabase to stay consistent |
| Increased later migration cost | **Yes** | you pay to build the bridge, then pay again to remove it, plus data-cleanup of divergence |

**10 of 10 failure modes materialize.** There is no subset of Strategy A that avoids them, because the conflict is structural (two writers, snapshot-preferred read), not incidental.

## 3. Assessment of the target-state principle

Principle: *"One business domain must have exactly one authoritative source of truth, one controlled write path, one consistent read model."*

**[REC] I fully endorse the proposed target for the job domain, with one clarification:**

| Concern | Target | Verdict |
| --- | --- | --- |
| Source of truth | Supabase `jobs` + related relational tables | ✔ correct |
| Write path | RPC / Edge Function only | ✔ correct |
| Read path | Supabase query / view / RPC only | ✔ correct — **and `get_app_bootstrap` must stop serving jobs from `app_snapshots`** |
| localStorage | UI prefs + isolated demo mode only | ✔ correct |
| Legacy snapshot sync | Disabled **for the job domain** | ✔ — remove `jobs` from `remoteSnapshot()` (app.js:1515) and `applyBackendSnapshot()` (app.js:1616) |
| Google Sheet | Archive/reference only | ✔ correct |
| Google Form | Apps Script relay → Edge Function → transactional RPC | ✔ — **route it through a transactional `create_job` RPC, not a raw table upsert**, so Form and WebApp share one validated write path |
| Authenticated WebApp users | `create_job` RPC directly | ✔ correct |
| Staff assignment/updates | record-level RPCs | ✔ correct |
| Completion | server-enforced PIN or pending-inspection fallback | ✔ correct (this is F-04, Critical) |
| Audit | server `audit_logs` + `job_timeline` | ✔ — RPCs currently write `audit_logs` but **not** `job_timeline` (F-14); fix in this phase |

Clarification: the Edge Function today upserts the `jobs` table directly (gf-ingest:61). To have **one** write path, the Edge Function should call the same `create_job` RPC that the WebApp uses (with a service context), so validation/sanitization/audit live in exactly one place.

## 4. Strategy comparison across the 10 dimensions

| # | Dimension | Strategy A (partial) | Strategy B (controlled core rebuild) |
| --- | --- | --- | --- |
| 1 | Architectural consistency | **Fails** — two SoT, snapshot-preferred read | **Achieves** the one-domain principle |
| 2 | Risk of data conflict | **High/guaranteed** (FACT-1) | **Low** — single writer, single reader |
| 3 | Security | Partial — Form secured but authz still client-side, snapshot bypass remains | **Strong** — authz + workflow enforced server-side |
| 4 | Regression risk | **Deceptively high** — silent divergence, hard to detect | Moderate, **controllable** with tests + flag + one cutover |
| 5 | Implementation effort | Low up front, **high total** (build bridge + later remove + reconcile) | **Higher up front (L–XL), lower total** |
| 6 | Future development speed | **Slowed** — every feature supports both paths | **Faster** — one model to build against |
| 7 | Rollback complexity | Superficially easy, but rollback ≠ consistency (divergent data persists) | Clean if done via DB restore + flag (see §8) |
| 8 | Testing requirements | Must test both paths + their interaction (combinatorial) | Test one path + a migration script |
| 9 | Cutover safety | No real cutover — two systems run indefinitely | Single, planned, reversible cutover |
| 10 | Long-term maintenance cost | **Highest** — permanent dual-path tax | **Lowest** — one coherent domain |

Strategy B wins or ties on every dimension except raw up-front effort, where A's advantage is illusory because A's total cost is higher.

## 5. Independent conclusion

**[REC] Replace the "secure webhook + turn on Form ingestion now" sequencing with Strategy B, scoped strictly to the job domain.** Do **not** enable any Supabase job write path until the job read path is also relational and the snapshot job-bridge is disabled. Turning on one writer before unifying the reader is the specific mistake that creates the half-migrated trap.

This is **not** a from-zero rewrite (explicitly out of scope and unjustified by evidence). The UI, render layer, and visible workflow are preserved; only the **data layer, authorization boundary, workflow enforcement, and resident intake** change. The in-memory `jobs` array can remain as a **read cache** that hydrates exclusively from Supabase.

## 6. Fate of the original Batch 1

**Expanded and absorbed, not kept standalone, not discarded.**

- The Batch 1 items (F-01 escape XSS, F-02 default password, F-06 CORS, F-07 webhook secret) remain valid and become **Phase 0 hardening** inside Strategy B.
- What changes: Batch 1 must **not** be shipped together with "Google Form creates jobs in Supabase" while the frontend still reads localStorage. The webhook is secured now, but **enabling ingestion into Supabase is gated behind the read-path migration.**

## 7. Exact boundary of the rebuild

**In scope (job domain only):**
- Relational schema for jobs already exists (`jobs`, `job_close_pins`, `job_timeline`, `job_attachments`) — wire the app to it.
- Read path: replace snapshot-based job loading with relational reads (RPC/view). Fix `get_app_bootstrap` to stop returning jobs from `app_snapshots`.
- Write paths: `create_job`, `assign_job`, `update_job_status`, `verify_job_completion` become the **only** job writers; WebApp and Edge Function both call them.
- Server enforcement: PIN validation, required evidence, status-transition rules, `job_timeline` + `audit_logs` on every transition.
- Resident intake unified: Google Form (via Edge→RPC) and authenticated WebApp (via RPC) converge on `create_job`.
- Job-domain tests (unit + RLS/RPC + one e2e happy path) **before** deleting the legacy job path.

**Out of scope (this phase):**
- Team/staff records, resident PII tables, announcements, organization, permissions storage migration (they may temporarily remain on the snapshot bridge **only after `jobs` is removed from the snapshot payload**).
- Routine PM, LINE OA, Web Push, Calendar, finance, multi-tenant.
- UI/CSS redesign.
- Splitting `app.js` for style. (You may extract a `jobsApi`/`workflow` module **only** where required to route writes through RPC — functional necessity, not cosmetics.)

## 8. What to preserve vs. disable

**Preserve (do not touch behavior/appearance):**
- All render functions and DOM structure (`jobRow`, `openJob`, `renderJobList`, dashboards, compact mode).
- The visible workflow and Thai/English labels.
- Status set, sub-status semantics, PIN UX, no-PIN fallback UX.
- The in-memory `jobs` array **as a read cache** (hydrated from Supabase).
- Existing relational schema and RLS (extend, don't replace).

**Disable (hard-off, not merely "deprecated"):**
- `jobs` field inside `remoteSnapshot()` (app.js:1515) and its application in `applyBackendSnapshot()` (app.js:1616) and `loadRemoteSnapshot()` (app.js:1546–1549) — jobs must never travel via snapshot again.
- The job branch of `get_app_bootstrap` that prefers `app_snapshots` over relational jobs (migration:442–447) — for jobs, always read relational.
- `save_client_snapshot` as a **job** write path — it must not persist jobs.
- Direct localStorage job writes (`saveJobs()`, app.js:1276) except in explicit demo mode.
- Legacy Apps Script job sync (`remoteRequest`/`queueRemoteSync` for jobs, app.js:1530–1588) — off for jobs.

"Disable" here means the code path is removed from the active flow behind a flag or deleted after tests pass — not left dormant where a future change could re-activate it.

## 9. Safe migration & cutover sequence

**[REC] One-way cutover, never two live writers.**

1. **Phase 0 — hardening (old Batch 1):** escape XSS, remove default `1234`, secure webhook (fail-closed secret + HMAC), restrict CORS. No behavior change to job storage yet.
2. **Server enforcement:** add PIN/evidence/transition checks + `job_timeline` writes inside the RPCs. Route the Edge Function through `create_job` RPC. Sanitize payload server-side.
3. **Read path swap (staging):** on `SUPABASE_ENABLED=true`, hydrate the `jobs` cache from a relational RPC/view; fix `get_app_bootstrap` to serve relational jobs. Remove `jobs` from the snapshot payload.
4. **Write path swap (staging):** point `createJob/assignJob/updateJobStatus/verifyCompletion` at the RPCs; keep the same function signatures so render code is untouched.
5. **Tests green** (§ Definition of Done) on staging with **fake data**.
6. **One-time data import:** script migrates any real localStorage jobs → Supabase via `create_job` (idempotent by a stable key), run once, verified row counts.
7. **Cutover:** flip the job backend flag to Supabase in the target environment. From this instant, Supabase is the sole authority; localStorage jobs become read-only demo artifacts.
8. **Decommission:** after a soak period, delete the legacy job write code paths.

No step ever has both localStorage and Supabase accepting job writes simultaneously.

## 10. Rollback plan that does not reintroduce two sources of truth

**[REC]** Rollback is **backward along the same single-authority axis**, not "fall back to localStorage."

- **Before cutover:** rollback = redeploy previous frontend build (still localStorage/demo). Trivial; no divergence because Supabase job writes were never enabled outside staging.
- **After cutover:** authority is Supabase. Rollback = **restore Supabase to the pre-incident snapshot (DB backup/point-in-time)** and redeploy the prior frontend that reads Supabase. **Do not** re-enable localStorage-as-SoT — that would recreate two sources. localStorage remains demo-only.
- Keep a tagged release + migration-down script. The invariant: at any moment exactly one system is authoritative for jobs.

## 11. Definition of Done (proves not half-migrated)

The job domain is done when **all** hold:
1. No code path writes jobs to localStorage except an explicitly isolated demo mode.
2. `remoteSnapshot()` / `applyBackendSnapshot()` contain **no** `jobs` field; `get_app_bootstrap` serves jobs only from relational tables.
3. Every job create/assign/update/complete goes through a Supabase RPC; there is exactly one job-id scheme.
4. Server rejects: completion without valid PIN (or forces pending-inspection), missing required evidence, and illegal status transitions — proven by tests (AT-4, AT-5, AT-7).
5. Every transition writes `job_timeline` **and** `audit_logs` (server-side, immutable).
6. Google Form and authenticated WebApp both create jobs via the same `create_job` RPC; idempotent by `external_id`/idempotency key (AT-10).
7. A resident cannot read another room's job; staff cannot bypass via snapshot (RLS tests, AT-8).
8. Automated suite green: unit (validate/conflict/permission), RLS/RPC, one e2e happy path, XSS (AT-11).
9. Grep shows the legacy job write paths removed or unreachable outside demo.
10. With `app_snapshots` populated, a Form-ingested job **is** visible in the WebApp (the FACT-1 regression is closed).

## 12. Revised implementation prompt for Opus (use ONLY after approval)

> **Scope:** Migrate the **job domain only** to Supabase as the single source of truth. Preserve all existing UI, DOM structure, CSS, Thai/English labels, and visible workflow. Do not add PM/LINE/Push/Calendar/finance/multi-tenant. Do not split `app.js` for style; extract a job API/workflow module only where functionally required to route writes through RPC. Do not deploy or use production data; work against a staging Supabase project with fake data.
>
> **Deliver in order, each behind tests:**
> 1. Hardening: `esc()` all user/external fields entering the DOM (app.js:3276, 4403, 4417–4427; profiles.js:89,151); replace default password `1234` with per-account random + forced reset (keep seed demo accounts flagged demo-only); Edge Functions fail-closed on missing webhook secret + restrict CORS to trusted origins.
> 2. Server enforcement in RPCs (`update_job_status`, `verify_job_completion`, `create_job`): PIN check on completion or force `pending_inspection` + `waiting_owner_or_admin_verification`; required-evidence and status-transition validation; write `job_timeline` + `audit_logs` on every transition; sanitize inputs.
> 3. Route `google-forms-ingest` through `create_job` RPC (service context), idempotent by `external_id`.
> 4. Read path: hydrate the in-memory `jobs` cache exclusively from a relational RPC/view; fix `get_app_bootstrap` to serve jobs relationally; remove `jobs` from `remoteSnapshot()`/`applyBackendSnapshot()`.
> 5. Write path: repoint `createJob/assignJob/updateJobStatus/verifyCompletion` to the RPCs, preserving their signatures so render code is unchanged.
> 6. One-time import script: localStorage jobs → Supabase via `create_job`, idempotent, verified counts.
> 7. Tests: unit (`validateStatusUpdate`, `checkScheduleConflict`, permission fns), RLS/RPC (AT-4,5,7,8,10,12), e2e happy path, XSS (AT-11).
> 8. Feature flag `JOBS_BACKEND = supabase | demo`; single-authority cutover; no dual live writers.
>
> **Definition of Done:** section 11 of `docs/audit/13-architecture-reassessment-job-domain.md`. Stop after each numbered deliverable for review. Do not remove legacy job write code until items 4–7 pass on staging.

---

## Assumptions & residual uncertainty

- **[ASSUMPTION]** Staging Supabase project is available for testing; production remains untouched. (Not yet provisioned — see open questions.)
- **[ASSUMPTION]** Real job data volume is small (README: ~30 users), so a one-time import is cheap.
- **[FACT/limit]** Not runtime-verified against a live Supabase instance; FACT-1 is derived from reading `get_app_bootstrap` (migration:437–458) and the render/data-load code, which is unambiguous but should be confirmed once staging exists.
- **[RISK]** Other domains (resident PII, team) still ride the snapshot bridge after this phase; that is acceptable **only** once `jobs` is removed from the snapshot payload, and those domains are the next migration target.
