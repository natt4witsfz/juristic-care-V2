# Prompt For Next Codex Agent

Use this prompt in the next Codex account/thread.

```text
You are taking over the Juristic Care V2 repository.

Repository:
C:\Projects\juristic-care-V2

GitHub:
https://github.com/ort83tester-arch/juristic-care-V2.git

Current branch:
feat/stage-5-legacy-import

Expected latest commit:
a8fb2b7 feat: add profile PIN onboarding flow

Important URLs:
- Pre-Production: https://juristic-care-v2-preprod.mitratiwa.chatgpt.site
- Production: https://juristic-care-v2.mitratiwa.chatgpt.site

Project IDs:
- Pre-Production Sites: appgprj_6a5275267d8481918257207f7d8df2f2
- Production Sites: appgprj_6a527385dc688191abc5b6c7aa057ee3
- Supabase Staging ref: wdqadjikpkclmihbnfgg

Read these handoff files first:
- handoff/00-READ-ME-FIRST.md
- handoff/01-CURRENT-STATE.md
- handoff/02-RECENT-WORK-COMPLETED.md
- handoff/03-SECURITY-AND-SECRETS.md
- handoff/04-DEPLOYMENT-RUNBOOK.md
- handoff/05-PREPROD-TESTING.md
- handoff/06-NEXT-WORK.md
- handoff/07-FILE-MAP.md

Before editing:
1. cd C:\Projects\juristic-care-V2
2. git status --short
3. git branch --show-current
4. git log -5 --oneline
5. npm run check
6. npm test

Expected baseline:
- npm run check passes
- npm test passes with 72 tests, 57 pass, 0 fail, 15 todo

Production rules:
- Do not touch Production without explicit approval.
- Do not run production build/deploy without Bit-code approval.
- Never ask the user to paste Secret Keys in chat.
- Never display, log, hash, screenshot, or serialize Secret Keys.
- Use Staging only unless explicitly approved.

Current important implementation:
- Post-login onboarding flow exists in profiles.js.
- Flow: Login -> Choose Profile -> 6-digit PIN -> Interface Design -> Application.
- Full/Compact interface exists in app.js.
- Account menu flyout is side-positioned.
- Pre-Production public version 5 is deployed.
- New backend migration exists but should be applied to Staging only first:
  supabase/migrations/202607120001_profile_onboarding_stage.sql

Recommended next work:
1. Apply/verify the onboarding migration on Supabase Staging only.
2. Wire profiles.js to Supabase RPC wrappers when SUPABASE_ENABLED=true.
3. Add real secure PIN delivery provider.
4. Add browser E2E tests for the onboarding flow.
5. Keep Production untouched until separately approved.
```

