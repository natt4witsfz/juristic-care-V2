# Current State

## Repository

```text
C:\Projects\juristic-care-V2
```

Branch:

```text
feat/stage-5-legacy-import
```

Latest commit:

```text
a8fb2b7 feat: add profile PIN onboarding flow
```

Recent commits:

```text
a8fb2b7 feat: add profile PIN onboarding flow
1f4bc19 ui: show account menu as side flyout
62604ca deploy: serve preproduction static assets from worker
2a366e8 deploy: require Bit code for production promotion
71f56b7 deploy: add preproduction promotion workflow
```

## Runtime Mode

Committed `config.js`:

```js
SUPABASE_ENABLED: false
DEV_SHOW_PROFILE_PIN: false
```

Meaning:

- Source defaults are safe for Production: development PIN display is off.
- Pre-Production build script turns `DEV_SHOW_PROFILE_PIN` on only in the built `dist/config.js`.
- Current public Pre-Production is demo/fake-data UAT, not real resident-data production.

## URLs

Pre-Production:

```text
https://juristic-care-v2-preprod.mitratiwa.chatgpt.site
```

Production:

```text
https://juristic-care-v2.mitratiwa.chatgpt.site
```

Do not deploy Production unless explicitly approved.

## Hosting Config

Pre-Production:

```text
.openai/hosting.preproduction.json
project_id: appgprj_6a5275267d8481918257207f7d8df2f2
```

Production:

```text
.openai/hosting.json
.openai/hosting.production.json
project_id: appgprj_6a527385dc688191abc5b6c7aa057ee3
```

## Supabase

Staging project ref:

```text
wdqadjikpkclmihbnfgg
```

Applied Stage 5 migrations previously reported:

```text
202607110001_import_legacy_job_stage5.sql
202607110002_import_notes_array_fix.sql
202607110003_import_evidence_path_regex_fix.sql
```

New migration added but not confirmed applied in this handoff:

```text
supabase/migrations/202607120001_profile_onboarding_stage.sql
```

This new migration supports backend-owned profile onboarding:

- account profile selection
- one Owner profile handling
- temporary 6-digit profile PIN challenges
- interface preferences

Apply only to Staging first. Production remains untouched.

