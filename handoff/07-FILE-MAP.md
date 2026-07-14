# File Map

## Main Frontend

```text
index.html
styles.css
app.js
profiles.js
supabase-client.js
config.js
js/security.js
```

Important notes:

- `app.js` contains main app shell, login, navigation, full/compact interface, work order UI.
- `profiles.js` wraps `showApp()` and controls post-login profile/PIN onboarding.
- `supabase-client.js` contains frontend adapter wrappers for Supabase RPC calls.
- `config.js` remains safe by default: `SUPABASE_ENABLED: false`, `DEV_SHOW_PROFILE_PIN: false`.

## Deployment

```text
scripts/build-sites-static.mjs
scripts/confirm-production-promotion.ps1
.openai/hosting.preproduction.json
.openai/hosting.json
.openai/hosting.production.json
```

## Supabase

```text
supabase/migrations/
supabase/functions/
supabase/tests/
supabase-schema.sql
```

Most recent onboarding migration:

```text
supabase/migrations/202607120001_profile_onboarding_stage.sql
```

Stage 5 legacy import driver:

```text
scripts/import-legacy-jobs.mjs
scripts/legacy-sample-jobs.json
```

## Tests

```text
test/security.test.js
test/source-guards.test.js
test/stage3-read-path.test.js
test/stage4-write-path.test.js
test/stage5-import.test.js
test/profile-onboarding.test.js
test/pending-future-stages.test.js
```

Run all:

```powershell
npm test
```

## Handoff Docs

```text
handoff/00-READ-ME-FIRST.md
handoff/01-CURRENT-STATE.md
handoff/02-RECENT-WORK-COMPLETED.md
handoff/03-SECURITY-AND-SECRETS.md
handoff/04-DEPLOYMENT-RUNBOOK.md
handoff/05-PREPROD-TESTING.md
handoff/06-NEXT-WORK.md
handoff/07-FILE-MAP.md
handoff/08-CODEX-PROMPT-FOR-NEXT-AGENT.md
```

