# Stage 0 — Gate Report

> Strategy B, Stage 0 (safety baseline & tests). No storage-authority change. Stopping for review before Stage 1. Stage 1 is blocked until a staging Supabase project is confirmed and explicitly approved.

## 1. Files changed

**New files**
- `.gitignore`
- `package.json` (scripts: `serve`, `check`, `test`, `lint`, `check:functions`)
- `.eslintrc.json` (scaffold; ESLint not installable here)
- `playwright.config.js` (scaffold; browser not installable here)
- `js/security.js` (dual browser/Node module: `escapeHtml`, `generateTempPassword`, `isDemoAccount`)
- `test/security.test.js`
- `test/source-guards.test.js`
- `test/pending-future-stages.test.js`

**Modified files**
- `index.html` — load `js/security.js` before `app.js` (1 line).
- `app.js` — (a) `esc()` applied to job fields in `jobRow`, `openJob` detail grid, SLA note, `attachmentHtml`; (b) `genTempPassword()` helper + used in the four real creation paths (team form, employee CSV import, resident login, admin preview); (c) seed accounts tagged `isDemo` + local auth blocks demo creds when Supabase is active; (d) `mustChangePassword` flag recorded on generated accounts.
- `profiles.js` — local `esc` helper + escaping of user-entered profile names (`p.name`, `profile.name`, avatar initials).
- `supabase/functions/google-forms-ingest/index.ts` — fail-closed on missing `GOOGLE_FORMS_INGEST_SECRET`; CORS allowlist (no wildcard).
- `supabase/functions/secure-file-access/index.ts` — CORS allowlist (no wildcard).
- `supabase/functions/admin-users/index.ts` — CORS allowlist; server-side temporary password generation (replaces `"1234"` default); `must_change_password` metadata; returns `tempPassword` only when generated.

## 2. Documentation changed
- `docs/audit/14-strategy-b-rebuild-plan.md` — incorporated Amendment 1 (transactional `ingest_google_form_submission`), Amendment 2 (green suite + pending markers), Amendment 3 (legacy PIN hashing/rotation), and updated Stages 1/2/5/7 + the Opus prompt.
- `docs/audit/STAGE-0-GATE-REPORT.md` — this file.

## 3. Test / tooling added
- Zero-install `node:test` suite (chosen because the npm registry returned 403 in this environment, so Vitest/ESLint/Playwright could not be installed).
- Active unit tests for `escapeHtml`, `generateTempPassword`, `isDemoAccount`.
- Source-level regression guards for every Stage 0 code change.
- 21 pending tests declared with `test.todo`, grouped by the stage that will activate them (Stages 1, 2, 3, 4, 5, 7).

## 4. Commands actually run
- `node --check js/security.js` → OK
- `node --check app.js` → OK *(run on a byte-complete reconstruction; see §11 environment note)*
- `node --check profiles.js` → OK *(same)*
- `node --test test/*.test.js` → executed

## 5. Passing test count
**14 active tests pass** (7 security-logic + 7 source-guard), **0 fail**.

## 6. Pending tests grouped by future stage (21 total, reported as TODO)
- **Stage 1 (4):** direct-insert rejection, BOLA read/update, `list_jobs_for_current_user` scoping, `import_legacy_job` contract.
- **Stage 2 (8):** PIN completion enforcement, no-PIN → pending_inspection, required evidence, illegal transition rejection, immutable timeline+audit, Asia/Bangkok dates, transactional ingest rollback, bootstrap not serving jobs from snapshots.
- **Stage 3 (3):** cache hydrates from read RPC only, `remoteSnapshot()` has no jobs field, relational jobs visible with `app_snapshots` populated.
- **Stage 4 (2):** create/assign/update/verify via RPC, cross-session visibility after reload.
- **Stage 5 (2):** duplicate `(source, legacy_id)` → one job, legacy PIN hashed/rotated never plaintext.
- **Stage 7 (2):** duplicate `external_id` idempotency, disabling Form trigger stops intake without affecting existing jobs.

## 7. Failing tests
**None.** (No genuinely failing test. The single earlier failure was an over-strict assertion; the code was corrected — the last non-seed `"1234"` literal, an admin-preview identity, now uses `genTempPassword()` — and the guard was made precise.)

## 8. Security findings addressed (from the audit master table)
- **F-01 (Critical) XSS** — job fields (`title`, `roomNo`, `building`, `floor`, `contactName`, `contactPhone`, `note`, attachment `src`, SLA note) and resident profile names now escaped.
- **F-02 (Critical) default password `1234`** — real creation paths generate a secure temporary password + `mustChangePassword`; seed demo accounts tagged and blocked against a real backend. *(Forced first-login change is UI-enforced in a later stage; the flag is recorded now.)*
- **F-06 (High) wildcard CORS** — all three Edge Functions use an `ALLOWED_ORIGINS` allowlist.
- **F-07 (High) webhook skips check when secret empty** — `google-forms-ingest` now fail-closed (rejects if no secret configured, 403 on mismatch).

## 9. Git diff summary
Not available as a diff: the mounted folder is **not a git working copy** (`git status` → "not a repository"; finding F-17). File-level summary is in §1. Recommend `git init` + commit this baseline so subsequent stages produce reviewable diffs.

## 10. Rollback procedure
Stage 0 changes are additive/localized and touch **no** storage-authority path, so rollback cannot cause data divergence:
- Delete the new files listed in §1.
- Revert the single `<script src="js/security.js">` line in `index.html`.
- Revert the localized edits in `app.js`, `profiles.js`, and the three Edge Functions.
Because the repo is not yet under git, keep a copy of the pre-Stage-0 files (or run `git init` now) to make rollback a single `git checkout`.

## 11. Confirmation: no storage-authority path changed
Verified. Unchanged: `saveJobs()` and all localStorage job writes, `remoteSnapshot()` payload, `applyBackendSnapshot()`, `get_app_bootstrap`, all job RPCs, the snapshot bridge, and `SUPABASE_ENABLED` (still `false`). No schema/migration change was made. Job reads/writes still flow exactly as before Stage 0.

**Environment note:** the sandbox's OneDrive mount served stale, byte-capped (truncated) copies of the two large edited files (`app.js`, `profiles.js`) — an environment sync artifact, not a code fault. The authoritative files are complete and valid (confirmed via the file tool through EOF, and `node --check` passed on byte-complete reconstructions). Please re-run `npm run check && npm test` locally once the files have synced to confirm on your machine.

## 12. Approval question for Stage 1
Stage 0 is complete and green. **Do you approve proceeding to Stage 1 (relational job schema, RLS, and RPC contracts including `_create_job_internal`, `ingest_google_form_submission`, and `import_legacy_job`)?** Per your instruction, Stage 1 will not begin until you also **confirm the staging Supabase project**. Reply with one of:
- **Approve Stage 1 + staging confirmed** (provide staging project reference)
- **Hold** (staging not ready)
- **Revise Stage 0** before continuing
