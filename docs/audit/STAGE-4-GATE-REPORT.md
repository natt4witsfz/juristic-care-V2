# STAGE 4 GATE REPORT — Frontend relational job write path

> Date: 2026-07-11 · Branch: `feat/stage-4-frontend-relational-write` ·
> Baseline: Stage 3 closed and tagged `stage-3-staging-verified` (commit
> `4443096`). Per the stage-gate protocol in
> `docs/audit/14-strategy-b-rebuild-plan.md` §7.
> **Hard stop — Stage 5 not started. No migration created or applied. Form
> trigger disabled. `SUPABASE_ENABLED` remains false. Not yet
> staging-validated.**

## 1. What Stage 4 does

In Supabase mode, every frontend job mutation now goes through the approved
Stage 2 server RPCs — the server remains the sole enforcement point for
transitions, evidence, PIN verification, the no-PIN inspection flow,
authorization, timeline and audit:

| Action | RPC | Frontend facade |
| --- | --- | --- |
| Create job | `create_job(p_payload)` | `createJob()` |
| Assign job | `assign_job(p_job_id, p_assignee_id, p_extra)` | `assignJob()` |
| Update status/progress | `update_job_status(p_job_id, p_payload)` | `updateJobStatus()` |
| Verify completion | `verify_job_completion(p_job_id)` | `verifyCompletion()` |

The original demo bodies are preserved verbatim as `createJobLocal` /
`assignJobLocal` / `updateJobStatusLocal` / `verifyCompletionLocal` and run
unchanged when `SUPABASE_ENABLED=false`. Function signatures and the visible
UI flow are unchanged; call sites now `await` the facades and fail closed.

## 2. Cache authority

After every successful mutation the cache refreshes **only** through
`loadJobsFromSupabase()` (`list_jobs_for_current_user`). RPC return objects
are never pushed, merged or normalized into the cache — the `create_job`
result is used solely to split off the one-time `closePin` and the new job
id, then discarded. On RPC failure nothing mutates the cache and the user
sees a bilingual Thai/English error (`jobMutationErrorText` maps
`PIN_INVALID`, `EVIDENCE_REQUIRED`, `ILLEGAL_TRANSITION`, `FORBIDDEN`,
`AUTH_REQUIRED`, `INVALID_INPUT`, upload failure, and a generic fallback).

## 3. Close PIN handling

- The one-time `closePin` returned by `create_job` is destructured away at
  the RPC boundary; it never passes through `normalizeJob` and never enters
  the jobs cache, localStorage, sessionStorage, snapshots, console logs,
  `addLog`, or audit payloads (test-enforced).
- It is displayed exactly once to the authorized creator via a native
  dialog immediately after creation (the same native-dialog pattern the app
  already uses for schedule-conflict confirmation), then the variable goes
  out of scope.
- `normalizeJob` no longer fabricates a fake `closePin` in Supabase mode
  (fixes finding F2 from the plan audit); the job-detail pin-card falls back
  to its existing masked variant for hydrated jobs.

## 4. Duplicate-submit protection

A module-level in-flight guard (`jobMutationInFlight`) rejects concurrent
create/assign/update/verify submissions and is released in `finally` on both
success and failure. The create payload additionally carries a generated
`idempotencyKey` (crypto.randomUUID), which the Stage 2 server contract uses
to return the existing job (without PIN) on a retry.

## 5. M5/M6 — user-administration pseudo-job (blocked in Supabase mode)

`requestOrDeleteUser()` (creates a local "delete user request" pseudo-job)
and the request-approval branch of `deleteUserNow()` are **blocked before any
jobs-array mutation** in Supabase mode with a clear bilingual message
("ฟังก์ชันคำขอลบผู้ใช้ยังไม่รองรับในโหมด Supabase / User-deletion request
workflow is not yet supported in Supabase mode"). No temporary job state, no
false success. Demo mode keeps both flows unchanged. Migrating this workflow
belongs to the user-management domain (future stage/ticket).

## 6. Documented limitations (accepted for Stage 4)

1. **Creation-time attachments (F4):** `create_job`'s frozen contract has no
   evidence parameter. In Supabase mode a create form containing attachments
   is **blocked before any Storage upload or RPC call** with a bilingual
   message directing the user to add photos via a status update after
   creation — so no orphaned Storage object can exist.
   **Future ticket:** extend the contract via a forward migration (evidence
   parameter on `create_job` or a companion RPC writing `job_attachments`
   transactionally), then lift the frontend block.
2. **Schedule-conflict metadata (F5):** conflict detection remains a
   client-side warning only (`confirm` dialog before assignment). The
   `hasScheduleConflict` / `conflictConfirmed*` fields are **not persisted
   server authority** — the Stage 2 whitelist drops them by design. The
   required `startTime`/`endTime` values **are** in the approved whitelist
   and are sent and persisted in `jobs.payload`.
3. **Status-update evidence upload fallback:** if a Storage upload fell back
   to a local dataURL, `mapEvidenceAttachments` throws **before** the RPC
   and the user sees an upload-failed error — no incomplete or known-invalid
   evidence payload is ever sent. (An upload that succeeded before a
   subsequently failed/blocked RPC submission can leave an unreferenced
   Storage object; those uploads only happen in the status-update flow that
   proceeds to the RPC, and the object remains private and harmless. Noted
   for the future evidence-RPC ticket.)

## 7. Files changed (exactly the five approved)

| File | Change |
| --- | --- |
| `app.js` | Mutation facades + local-body renames; `jobMutationErrorText`; `mapEvidenceAttachments`; in-flight guards; closePin isolation + `normalizeJob` guard; M5/M6 blocks; F4 pre-upload block; call sites await + fail closed; async-safe verify click handler; `pin` field mapping; DB-03 conditional `nextUpdateDate` |
| `test/stage4-write-path.test.js` | **New** — 12 active source-level guards |
| `test/pending-future-stages.test.js` | Stage 4 RPC TODO converted (activated in the new file); cross-session reload TODO retained |
| `docs/audit/STAGE-4-GATE-REPORT.md` | **New** — this report |
| `docs/audit/15-job-domain-rpc-contract.md` | Stage 4 consumption note (write paths + F4 limitation) |

Untouched: `supabase-client.js` (existing RPC wrappers already match the
contract), `config.js` (`SUPABASE_ENABLED: false`, empty placeholders),
`index.html`, CSS/DOM/labels, `profiles.js`, all migrations, Edge Functions,
Google Form ingestion.

## 8. Tests

`npm test`: **52 tests — 35 pass, 0 fail, 17 todo** (was 41: 23/0/18).
Twelve new active Stage 4 guards cover: correct RPC per mutation; refresh
only via the read RPC; RPC results never inserted into the cache; failure
paths mutate nothing and show bilingual errors; in-flight guard + release +
idempotency key; closePin isolation incl. the `normalizeJob` guard; M5/M6
blocked before mutation with bilingual messages; attachment-create blocked
before upload and before RPC; no upload reachable from any facade and
evidence validated before the RPC; `pin` mapping + evidence shape + DB-03;
demo bodies preserved; `startTime`/`endTime` in the payload with conflict
metadata not sent as authority. TODO converted:
"createJob/assignJob/updateJobStatus/verifyCompletion call RPCs".
Remaining TODOs (17): Stage 1/2 live-DB markers, Stage 4 cross-session
reload (needs staging), Stage 5, Stage 7.

## 9. Not runtime-verified (declared limits)

No staging validation has been performed for Stage 4: live create/assign/
update/verify against the staging RPCs, the one-time PIN dialog, error-path
behavior against real RPC failures, and the cross-session reload check all
await the approved staging session. Nothing here is claimed as live-tested.

## 10. Rollback point

`git checkout stage-3-staging-verified -- app.js test/ docs/audit/` (or
revert the Stage 4 commit once created) restores the verified Stage 3 tree.
Nothing was applied or deployed anywhere.

## 11. Approval request

**Go/no-go:** (1) approve one commit of the Stage 4 deliverables to
`feat/stage-4-frontend-relational-write` and push; (2) approve the Stage 4
staging validation session (uncommitted local override, publishable key,
fake data). Stage 5 (legacy import) will not begin without explicit
approval.
