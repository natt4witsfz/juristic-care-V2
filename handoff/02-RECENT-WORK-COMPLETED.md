# Recent Work Completed

## 1. Pre-Production Hosting Fix

Commit:

```text
62604ca deploy: serve preproduction static assets from worker
```

Fixed earlier 404 on:

```text
https://juristic-care-v2-preprod.mitratiwa.chatgpt.site
```

The static worker now embeds and serves the required assets.

## 2. Production Promotion Bit-Code Guard

Commit:

```text
2a366e8 deploy: require Bit code for production promotion
```

Important files:

```text
scripts/confirm-production-promotion.ps1
scripts/build-sites-static.mjs
docs/PREPRODUCTION-PROMOTION-WORKFLOW.md
```

Production build requires:

```text
PRODUCTION_PROMOTION_BIT_HASH
PRODUCTION_PROMOTION_BIT_CODE
PRODUCTION_PROMOTION_CONFIRM=PROMOTE_TO_PRODUCTION
```

The user asked earlier how Bit code is stored:

- Store only SHA-256 hash in environment/secret manager.
- Do not store plaintext Bit code in source, `.env`, reports, screenshots, chat, or Git.
- The script prompts locally and clears plaintext env variables afterward.

## 3. Account Menu Side Flyout

Commit:

```text
1f4bc19 ui: show account menu as side flyout
```

Changed:

- `index.html`
- `styles.css`
- `app.js`
- `docs/ASSIGNMENT-SYSTEM-DESIGN-UX.md`

Result:

- Clicking `•••` opens account menu as a side flyout beside the sidebar.
- Mobile fallback uses fixed positioning.
- `aria-expanded` is updated.
- Clicking outside closes the menu.

## 4. Profile PIN Onboarding Flow

Commit:

```text
a8fb2b7 feat: add profile PIN onboarding flow
```

Implemented flow:

```text
Login
-> Choose Profile
-> Verify 6-digit PIN
-> Choose Interface Design
-> Application
```

Files changed/created:

```text
profiles.js
app.js
supabase-client.js
styles.css
index.html
config.js
scripts/build-sites-static.mjs
docs/PROFILE-PIN-INTERFACE-ONBOARDING.md
supabase/migrations/202607120001_profile_onboarding_stage.sql
test/profile-onboarding.test.js
docs/00-DOCUMENTATION-INDEX.md
```

Security-relevant behavior:

- PIN length: 6 numeric digits
- Browser fallback uses `crypto.getRandomValues`
- No `Math.random` for profile PIN
- PIN hash stored, not plaintext
- 5-minute expiry
- one-time use
- 5 attempt limit
- reissue invalidates previous challenge
- default source config does not show dev PIN
- Pre-Production build enables dev PIN only for fake-data UAT

Deployed:

```text
Pre-Production version 5
https://juristic-care-v2-preprod.mitratiwa.chatgpt.site
```

Validation performed:

```text
npm run check
npm test
npm run build:preprod
```

Expected result:

```text
72 tests
57 pass
0 fail
15 todo
```

