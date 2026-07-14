# Recommended Next Work

## Highest Priority

1. Apply and verify the new onboarding migration on Supabase Staging only:

```text
supabase/migrations/202607120001_profile_onboarding_stage.sql
```

2. Add runtime integration between `profiles.js` and Supabase RPCs when `SUPABASE_ENABLED=true`.

Currently:

- RPC wrappers exist in `supabase-client.js`.
- Browser fallback implements demo flow when Supabase is off.
- Production-grade session enforcement still needs backend/session integration.

3. Create real PIN delivery:

- email
- LINE
- SMS
- or other approved secure channel

Development on-screen PIN must remain disabled in Production.

## Supabase Onboarding Work

New RPCs added by migration:

```text
ensure_owner_profiles
list_account_profiles
create_account_profile
select_account_profile
issue_profile_pin_challenge
verify_profile_pin_challenge
save_interface_preference
```

Frontend adapter methods added:

```text
listAccountProfiles
createAccountProfile
selectAccountProfile
issueProfilePinChallenge
verifyProfilePinChallenge
saveInterfacePreference
```

Next agent should wire these methods into `profiles.js` for `SUPABASE_ENABLED=true`.

## Production Readiness

Before Production:

- remove/demo-disable public demo credentials
- enable Supabase backend authority
- verify RLS and RPC ownership checks on Staging
- verify no profile PIN is exposed in production logs/UI
- verify `DEV_SHOW_PROFILE_PIN: false`
- verify Production build requires Bit code
- verify no Production data is touched during Staging tests

## Stage 5 Legacy Import

Previous expected state:

- Stage 5 implementation committed and pushed
- Staging migrations applied through:
  - `202607110001_import_legacy_job_stage5.sql`
  - `202607110002_import_notes_array_fix.sql`
  - `202607110003_import_evidence_path_regex_fix.sql`
- Dry-run and smoke test previously passed
- Dry-run mixed sample expected exit code 2 due intentional binary evidence failure

Do not perform real import without explicit separate approval.

## Useful Existing Docs

```text
docs/PROFILE-PIN-INTERFACE-ONBOARDING.md
docs/ASSIGNMENT-SYSTEM-DESIGN-UX.md
docs/PREPRODUCTION-PROMOTION-WORKFLOW.md
docs/PREPRODUCTION-SECURITY-REVIEW.md
docs/14-DEPLOY-RUNBOOK.md
docs/17-WORK-ASSIGNMENT-DETAIL-UX-SPEC.md
```

