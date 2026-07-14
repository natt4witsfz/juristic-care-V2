# Deployment Runbook

## Preflight

```powershell
cd C:\Projects\juristic-care-V2
git status --short
git branch --show-current
git log -1 --oneline
npm run check
npm test
```

Expected current branch:

```text
feat/stage-5-legacy-import
```

Expected current HEAD as of this handoff:

```text
a8fb2b7 feat: add profile PIN onboarding flow
```

## Build Pre-Production

```powershell
npm run build:preprod
```

This runs:

```text
node scripts/build-sites-static.mjs --environment preproduction
```

Pre-Production build behavior:

- adds PRE-PRODUCTION banner
- uses `.openai/hosting.preproduction.json`
- flips built `dist/config.js` to `DEV_SHOW_PROFILE_PIN: true`
- does not modify committed source `config.js`

## Build Production

Do not run unless Production promotion is explicitly approved.

```powershell
npm run build:production
```

Production build is guarded by:

```text
scripts/confirm-production-promotion.ps1
```

The build refuses to proceed without a valid Bit-code hash and local hidden prompt.

## Sites Deployment

Use Sites tooling because repo contains `.openai/hosting.json`.

Pre-Production project:

```text
appgprj_6a5275267d8481918257207f7d8df2f2
```

Production project:

```text
appgprj_6a527385dc688191abc5b6c7aa057ee3
```

Important:

- Deploy only saved Sites versions.
- For public deployment, user approval should be explicit.
- For this handoff, Pre-Production public version 5 has already been deployed.

## Current Deployed Pre-Production

```text
https://juristic-care-v2-preprod.mitratiwa.chatgpt.site
```

Last validated after deploy:

- root URL returned `STATUS=200`
- Pre-Production banner present
- `profiles.js` bundle contains `PROFILE_SELECTED_PIN_REQUIRED`
- `PIN_LENGTH = 6` present
- no `Math.random` in profile PIN code
- built `config.js` contains `DEV_SHOW_PROFILE_PIN: true`

