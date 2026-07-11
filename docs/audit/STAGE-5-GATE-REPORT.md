# STAGE 5 GATE REPORT - Legacy import & reconciliation

> Date: 2026-07-11. Branch: `feat/stage-5-legacy-import`.
> Staging project ref: `wdqadjikpkclmihbnfgg`.
> Production was not accessed or modified. Stage 6 has not started.

## 1. Gate Status

Stage 5 Section D dry-run validation is complete on Supabase Staging.

No real import was run. No `--commit` flag was used. `CONFIRM_IMPORT`
remained unset. Cleanup SQL was not run.

## 2. Staging Migration Evidence

`npx supabase migration list --linked` confirmed local and remote migration
history match through:

- `202607110001_import_legacy_job_stage5.sql`
- `202607110002_import_notes_array_fix.sql`
- `202607110003_import_evidence_path_regex_fix.sql`

The migration list showed no pending local migration after `202607110003`.

Prior Stage 5 verification evidence recorded before this Section D handoff:

- database lint passed with exit code `0`
- Stage 5 smoke test passed on Staging
- all smoke-test write sections were wrapped in `BEGIN` / `ROLLBACK`
- smoke validation left zero import residue

## 3. Driver Security Evidence

`scripts/import-legacy-jobs.mjs` now uses the modern Supabase Secret Key flow:

- reads `SUPABASE_URL`
- reads `SUPABASE_SECRET_KEY`
- does not read or use `SUPABASE_SERVICE_ROLE_KEY`
- sends the Secret Key only in the `apikey` header
- creates no `Authorization` header
- defaults to dry-run
- requires both `--commit` and exact `CONFIRM_IMPORT` only for a real import
- allowlist contains only Staging ref `wdqadjikpkclmihbnfgg`

Earlier Section D attempts established two important credential lessons:

- the first legacy service-role attempt failed locally before a valid request
  because the `apikey` header was invalid for the modern flow
- the first modern Secret Key validation attempts were rejected before a
  request because the validator was initially too restrictive

The corrected driver validates only the documented `sb_secret_` prefix plus
safe printable-token requirements. The Secret Key was never committed,
displayed, logged, hashed, serialized, stored in source, or written to a
report.

## 4. Dry-Run Method

Dry-runs used one temporary PowerShell script under the Windows TEMP
directory. The script contained no credential. It prompted once with
`Read-Host -AsSecureString`, converted the value only in memory, set only
`SUPABASE_SECRET_KEY` for the runtime process, cleared the clipboard, and
removed runtime environment variables and temporary files in a `finally`
block.

The committed fake sample contains 11 records. The embedded-binary evidence
record in the committed file is `LEG-0007-EV-BIN`. A temporary valid-only
subset outside the repository excluded exactly that one record and contained
10 records. `scripts/legacy-sample-jobs.json` was not modified.

## 5. Full Mixed Fake-Sample Dry-Run

Command:

```powershell
node scripts/import-legacy-jobs.mjs
```

Result:

- mode: `DRY-RUN`
- project ref: `wdqadjikpkclmihbnfgg`
- submitted: `11`
- validated/insertable label (`inserted`): `9`
- skipped: `1`
- failed: `1`
- expected failure: `EVIDENCE_BINARY_MIGRATION_REQUIRED`
- failed record: `LEG-0007-EV-BIN`
- acceptance gate: `FAIL` by design
- exit code: `2`

Exit code `2` is expected for the intentionally mixed fake sample and was
not a driver crash.

## 6. Valid-Only Fake-Subset Dry-Run

Command:

```powershell
node scripts/import-legacy-jobs.mjs --file "<TEMP valid subset path>"
```

Result:

- mode: `DRY-RUN`
- project ref: `wdqadjikpkclmihbnfgg`
- submitted: `10`
- validated/insertable label (`inserted`): `9`
- skipped: `1`
- failed: `0`
- acceptance gate: `PASS`
- exit code: `0`

In dry-run mode, `inserted` is the driver's reconciliation label for records
validated as insertable. No row was actually inserted.

## 7. Zero-Write Verification

Read-only Staging counts were captured before and after the dry-runs using
the existing Supabase CLI authenticated session, not the Secret Key.

| Count | Before | After |
| --- | ---: | ---: |
| imported legacy jobs | 0 | 0 |
| related `job_close_pins` | 0 | 0 |
| imported `job_timeline` rows | 0 | 0 |
| imported `job_attachments` rows | 0 | 0 |
| Stage 5 import audit rows | 0 | 0 |
| jobs with persisted `import_batch_id` | 0 | 0 |
| relevant Storage objects (`job-attachments/jobs/legacy/%`) | 0 | 0 |

`public.notifications` and `public.notification_logs` were not present in
the schema, so no notification rows were available for the import driver to
create.

Confirmed after the dry-runs:

- no import batch id was persisted
- no job was inserted
- no PIN row was inserted
- no timeline row was inserted
- no attachment row was inserted
- no import audit row was inserted by the driver
- no notification row was created
- no Storage object was created
- no cleanup SQL was run

## 8. Local Verification

Before and after the report update:

- `npm run check` passed with exit code `0`
- `npm test` passed with `66` total, `51` pass, `0` fail, `15` todo
- `git diff --check` passed with exit code `0`

Dry-run execution did not modify source or configuration files. The only
intended repository change after Section D is this gate report.

## 9. Scope Boundaries

No real resident data or real legacy export was used. No real import was
run. Production was not touched. Frontend files, `config.js`, Edge
Functions, and Google Form ingestion were untouched. The Google Form trigger
was not activated. Stage 6 did not begin.

Runtime cleanup removed:

- `SUPABASE_SECRET_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_URL`
- `CONFIRM_IMPORT`
- temporary valid-subset JSON files
- temporary PowerShell scripts
- temporary driver output files
- clipboard content that could have held the Secret value

## 10. Remaining Limitations
- embedded binary evidence still requires the future binary-evidence
  migration flow
- rotated legacy PINs still require a separately approved reissue path or the
  existing no-PIN/admin-verification operational flow
- no real legacy dataset has been imported
- no real import is approved by this report
