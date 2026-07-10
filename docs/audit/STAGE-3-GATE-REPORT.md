# STAGE 3 GATE REPORT — Frontend relational job read path

> Date: 2026-07-10 · Branch: `feat/stage-3-frontend-relational-read` ·
> Baseline: Stage 2 closed and tagged `stage-2-staging-verified` (commit
> `c6ac27c`). Per the stage-gate protocol in
> `docs/audit/14-strategy-b-rebuild-plan.md` §7.
> **Hard stop — Stage 4 not started. No migration created or applied. Form
> trigger disabled. `SUPABASE_ENABLED` remains false.**

## 1. Canonical frontend job read path (decision)

**`list_jobs_for_current_user()`** via `JuristicSupabase.listJobs()`
(supabase-client.js), called from `loadJobsFromSupabase()` (app.js).

Rationale: the RPC is already contract-frozen as "the only client job-read
path from Stage 3 onward" (doc 15 §1), carries the RLS/`can_read_job`
authorization and the complete relational-authoritative client shape, and
never exposes PIN material. `get_app_bootstrap()` remains in use **only for
non-job domains**; its `jobs` key (relational since Stage 2) is not consumed
by the frontend — `applyBackendSnapshot()` is job-blind, so even an old
snapshot with a stale `jobs` field is harmless. No direct table `SELECT` on
`jobs` exists in the frontend.

## 2. Single-authority behavior

With `SUPABASE_ENABLED=true` (runtime):

- The in-memory `jobs` array is a **render cache only**. It starts empty
  (never seeded from localStorage) and is **replaced atomically**
  (`jobs = rows.map(normalizeJob)`) after each successful RPC read — repeated
  bootstrap/reload cannot duplicate or merge.
- `saveJobs()` returns immediately: jobs are never written to localStorage
  and never queued into a snapshot save.
- `remoteSnapshot()` no longer contains a `jobs` field, so
  `save_client_snapshot` can never write job-domain data.
- `applyBackendSnapshot()` ignores any `jobs` field; old `app_snapshots`
  rows containing jobs remain harmless.
- The legacy Apps Script sync (`loadRemoteSnapshot`) no longer reads or
  writes jobs, and Supabase mode returns before ever reaching it.
- **Failure fails closed:** if the RPC read fails, the app shows a Thai/EN
  toast and schedules up to two automatic retries (5s apart); after the last
  failure it asks the user to reload. The session keeps only what it already
  loaded in memory (empty on first load). No fallback to stale local jobs —
  a failed read can never create a second job authority.
- Logout reloads the page; with no local job seed in Supabase mode, no job
  state survives the session.

With `SUPABASE_ENABLED=false` (committed default): the existing demo/local
behavior is preserved unchanged — localStorage seed/load/save, Apps Script
sync when configured, demo accounts. The mode switch is a single startup
check (`jobsRelationalMode`) plus the existing `supabaseEnabled()` guard.

## 3. Files changed

| File | Change |
| --- | --- |
| `app.js` | Initial job cache guarded by mode; `saveJobs()` no-op in Supabase mode; `remoteSnapshot()` jobs field removed; `applyBackendSnapshot()` / `loadRemoteSnapshot()` job handling removed; new `loadJobsFromSupabase()`; `loadBackendSnapshot()` rewired (jobs → RPC, snapshot job-blind, no Apps Script fallback in Supabase mode) |
| `supabase-client.js` | New `listJobs()` → `rpc("list_jobs_for_current_user")`, exported |
| `test/stage3-read-path.test.js` | **New** — 9 active source-level guards |
| `test/pending-future-stages.test.js` | 3 Stage 3 TODOs converted to active tests (moved to the new file) |
| `docs/audit/15-job-domain-rpc-contract.md` | Stage 3 note in §1 |
| `docs/audit/STAGE-3-GATE-REPORT.md` | **New** — this report |

Untouched: `index.html`, all CSS, DOM structure, labels, `config.js`
(`SUPABASE_ENABLED: false`, empty URL/key placeholders), `profiles.js`, all
migrations, all Edge Functions, the Form trigger.

## 4. Job-related localStorage/snapshot paths — full inventory

| Path (pre-Stage-3) | Disposition |
| --- | --- |
| `app.js` startup: `jobs = localStorage juristicJobsV2 \|\| seedJobs` + seed refresh write | **Guarded** — demo mode only (`jobsRelationalMode` check); Supabase mode starts `[]` |
| `saveJobs()` → `localStorage.setItem` + `queueBackendSync()` | **Guarded** — returns first in Supabase mode; demo behavior preserved |
| `remoteSnapshot().jobs` (fed both Apps Script save and `save_client_snapshot`) | **Removed** — job domain excluded from the snapshot bridge |
| `applyBackendSnapshot()` jobs block (assigned cache + wrote localStorage) | **Removed** — snapshot is job-blind |
| `loadRemoteSnapshot()` jobs block (Apps Script → cache + localStorage) | **Removed** — legacy job sync disabled |
| `loadBackendSnapshot()` fallback to `loadRemoteSnapshot()` on Supabase failure | **Removed in Supabase mode** — explicit return; fallback only in demo mode |
| Interior `saveJobs()` call sites (create/assign/update/verify/delete demo paths) | **Preserved & deferred** — they mutate only the in-memory cache in Supabase mode (self-guarded `saveJobs`); repointing these writers to RPCs is **Stage 4**; hard removal of demo-write authority is **Stage 6** |
| `sessionStorage juristicUser`, UI preference keys (lang, view modes, calendar, filters) | **Preserved** — not job-domain data |

## 5. Tests

`npm test`: **41 tests — 23 pass, 0 fail, 18 todo** (was 35: 14/0/21).
Nine new active Stage 3 guards prove: cache hydrates only from the read RPC
(atomic assignment, no merge/append, no direct table select);
`remoteSnapshot()` has no jobs; `applyBackendSnapshot()` ignores snapshot
jobs and cannot write local jobs; bootstrap hydrates jobs before the
job-blind snapshot apply; stale localStorage jobs cannot override
(mode-guarded startup + no-op `saveJobs`); Apps Script sync carries no jobs;
failed reads fail closed with visible error + bounded retry and no local
fallback; demo mode behavior retained with `SUPABASE_ENABLED: false`; no
Secret Key / `service_role` / JWT / project URL in any frontend file.
Remaining 18 TODOs are Stage 4/5/7 and live-DB items, unchanged.

## 6. Items requiring live staging validation (not claimed here)

- A job visible from the RPC appears after login/reload in a real browser.
- A job absent from Supabase cannot be restored by localStorage (runtime).
- A populated `app_snapshots` row with stale jobs does not affect the view.
- DB-created jobs visible in a second browser session after reload.
- Retry/error toast behavior against a real failing endpoint.

Safe temporary override for that validation (do **not** commit): serve the
app locally and, in the browser console **before** app.js loads (or via a
local uncommitted copy of `config.js`), set `SUPABASE_ENABLED: true` with the
staging URL and the **publishable (anon) key only**. Never a service_role or
secret key; never committed.

## 7. Validation results

| Command | Result |
| --- | --- |
| `npm run check` | PASS (all 5 JS files) |
| `npm test` | 41 tests — 23 pass, 0 fail, 18 todo |
| `git diff --check` | clean |
| localStorage/snapshot job-path search | all paths inventoried in §4; none active in Supabase mode |

Confirmations: `SUPABASE_ENABLED` remains **false**; no key or secret
committed; **no database migration created or applied** (none was needed —
no schema defect found); no Supabase resource modified; Google Form trigger
disabled; Stage 4 not started.

## 8. Rollback point

`git checkout stage-2-staging-verified -- app.js supabase-client.js test/`
(or revert the Stage 3 commit once created) restores the exact verified
Stage 2 tree; nothing was applied or deployed anywhere.

## 9. Approval request

**Go/no-go:** (1) approve one commit of the Stage 3 deliverables to
`feat/stage-3-frontend-relational-read`; (2) approve the Stage 3 staging
validation session (§6, uncommitted local override with the publishable key
against staging fake data). Stage 4 (record-level write path) will not begin
without explicit approval.
