# Universal AI Continuation Prompt

ใช้ prompt นี้สำหรับส่งต่อให้ AI coding agent ตัวถัดไป เช่น Antigravity, Claude, Codex หรือ agent อื่นที่ทำงานกับ repository นี้

> เป้าหมาย: ให้ agent อ่านไฟล์ handoff, เข้าใจสถานะ Pre-Production/Production, รัน mockup/local validation ได้, และทำงานต่อโดยไม่แตะ Production หรือ secrets โดยไม่ได้รับอนุมัติ

---

## Prompt

```text
You are taking over the Juristic Care V2 WebApp repository as a senior coding agent.

Please reply to the user in Thai unless the user explicitly asks otherwise.

Repository:
C:\Projects\juristic-care-V2

GitHub:
https://github.com/ort83tester-arch/juristic-care-V2.git

Current expected branch:
feat/stage-5-legacy-import

Expected latest handoff commit:
86206d1 docs: add Codex handoff package

Important deployed URLs:
- Pre-Production: https://juristic-care-v2-preprod.mitratiwa.chatgpt.site
- Production: https://juristic-care-v2.mitratiwa.chatgpt.site

Project IDs:
- Pre-Production Sites project: appgprj_6a5275267d8481918257207f7d8df2f2
- Production Sites project: appgprj_6a527385dc688191abc5b6c7aa057ee3
- Supabase Staging ref: wdqadjikpkclmihbnfgg

Production safety:
- Do not touch Production unless the user gives explicit separate approval.
- Do not run production build or production deployment unless the Bit-code approval flow is explicitly requested and approved.
- Treat Production as read-only by default.
- Work on Pre-Production or local mockup first.

Secrets safety:
- Never ask the user to paste Secret Keys into chat.
- Never display, echo, print, hash, partially reveal, log, serialize, screenshot, or commit any Secret Key.
- Never put secrets in source files, config files, .env, command arguments, reports, screenshots, Git commits, or deployment logs.
- For Supabase Stage 5 import, use only SUPABASE_SECRET_KEY in a temporary runtime environment.
- Do not use SUPABASE_SERVICE_ROLE_KEY.
- Do not use --commit or CONFIRM_IMPORT unless explicitly approved.

First actions:
1. cd C:\Projects\juristic-care-V2
2. Read these files completely before changing code:
   - handoff/00-READ-ME-FIRST.md
   - handoff/01-CURRENT-STATE.md
   - handoff/02-RECENT-WORK-COMPLETED.md
   - handoff/03-SECURITY-AND-SECRETS.md
   - handoff/04-DEPLOYMENT-RUNBOOK.md
   - handoff/05-PREPROD-TESTING.md
   - handoff/06-NEXT-WORK.md
   - handoff/07-FILE-MAP.md
   - handoff/08-CODEX-PROMPT-FOR-NEXT-AGENT.md
   - handoff/09-UNIVERSAL-AI-CONTINUATION-PROMPT.md
3. Confirm:
   - current branch
   - latest commit
   - git status
   - whether working tree is clean
4. Run:
   - npm run check
   - npm test
5. Report the exact result before making changes.

Expected baseline:
- npm run check passes
- npm test passes with 72 tests, 57 pass, 0 fail, 15 todo

Current architecture summary:
- Static vanilla JavaScript WebApp
- Main app: app.js
- Post-login profile/PIN/interface onboarding: profiles.js
- Supabase browser adapter: supabase-client.js
- HTML/CSS: index.html, styles.css
- Runtime config: config.js
- Committed config defaults to:
  - SUPABASE_ENABLED: false
  - DEV_SHOW_PROFILE_PIN: false
- Pre-Production build flips DEV_SHOW_PROFILE_PIN to true only inside dist/config.js for fake-data UAT.

Current important implemented flow:
Login
-> Choose Profile
-> Verify 6-digit PIN
-> Choose Interface Design
-> Enter Application

Interface modes:
- FULL
- COMPACT

Pre-Production currently deployed:
- Version 5
- URL: https://juristic-care-v2-preprod.mitratiwa.chatgpt.site
- This is demo/fake-data UAT mode, not real Production data mode.

Local mockup / local validation instructions:
1. Run static checks:
   npm run check
   npm test
2. Build Pre-Production bundle:
   npm run build:preprod
3. Confirm dist/config.js contains:
   DEV_SHOW_PROFILE_PIN: true
4. Confirm source config.js still contains:
   DEV_SHOW_PROFILE_PIN: false
5. Serve the repo or dist locally only for UI inspection.

Preferred local mockup server options:

Option A, from repo root:
python -m http.server 4173

Then open:
http://localhost:4173

Option B, from dist after preprod build:
cd dist
python -m http.server 4174

Then open:
http://localhost:4174

If Python command differs on Windows, try:
py -m http.server 4173

Manual mockup test checklist:
1. Open local URL or Pre-Production URL.
2. Login with a demo account.
3. Confirm app does not enter dashboard immediately.
4. Confirm Choose Profile appears.
5. Confirm Owner profile appears first.
6. Add Tenant or Resident profile if needed.
7. Select profile.
8. Confirm Verify PIN page appears.
9. Confirm PIN is 6 numeric digits.
10. In Pre-Production/local fake-data mode, use the displayed development PIN.
11. Confirm wrong PIN shows an error and does not proceed.
12. Confirm correct PIN goes to Interface Design selection.
13. Choose Full Interface and verify full dashboard/sidebar.
14. Open account menu with the ••• button and verify side flyout.
15. Use Change Interface Mode and choose Compact Interface.
16. Verify compact layout.
17. Logout and login again to confirm interface preference restore.

Do not create duplicate authentication/profile/layout systems.
Use the existing:
- app.js login and interface picker
- profiles.js onboarding wrapper
- supabase-client.js adapter
- existing CSS design language

When implementing:
- Prefer small, scoped changes.
- Preserve existing features.
- Add tests for changed behavior.
- Update docs when behavior changes.
- Run npm run check and npm test before reporting completion.
- If deploying, deploy only Pre-Production unless Production is explicitly approved.

When reporting back:
Include:
1. What was read
2. Current branch and commit
3. Git status
4. Tests run and exact results
5. Files changed
6. Whether local mockup or Pre-Production was tested
7. Any risks or limitations
8. Explicit statement that Production was not touched

Never claim tests, deploys, or mockup checks passed unless actually executed.
```

---

## Short Version

ใช้เมื่อ agent มี context จำกัด:

```text
Work in C:\Projects\juristic-care-V2 on branch feat/stage-5-legacy-import.
Read handoff/00-READ-ME-FIRST.md through handoff/09-UNIVERSAL-AI-CONTINUATION-PROMPT.md before editing.
Reply in Thai.
Do not touch Production.
Do not expose or request secrets.
Run git status, npm run check, npm test first.
Use Pre-Production/local mockup only unless Production is explicitly approved.
Current Pre-Production: https://juristic-care-v2-preprod.mitratiwa.chatgpt.site
Current Production: https://juristic-care-v2.mitratiwa.chatgpt.site
Expected baseline: npm test = 72 tests, 57 pass, 0 fail, 15 todo.
Current important flow: Login -> Choose Profile -> 6-digit PIN -> Choose Interface -> App.
If testing mockup locally: npm run build:preprod, then serve repo or dist with python -m http.server.
Report exact checks and confirm Production was not touched.
```

