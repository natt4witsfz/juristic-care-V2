# Security And Secrets

## Critical Rules

- Never ask the user to paste Supabase Secret Key into chat.
- Never display, echo, print, hash, partially reveal, log, serialize, screenshot, or report any Secret Key.
- Never put secrets in source files, config files, `.env`, command arguments, reports, screenshots, or Git.
- Never touch Production unless separately approved.
- Use Staging only unless the user explicitly confirms Production promotion.

## Supabase Stage 5 Import Secrets

Modern Secret Key variable:

```text
SUPABASE_SECRET_KEY
```

Required URL for Staging:

```text
SUPABASE_URL=https://wdqadjikpkclmihbnfgg.supabase.co
```

Rules:

- Use only Staging Secret Key beginning with `sb_secret_`.
- Do not use `SUPABASE_SERVICE_ROLE_KEY`.
- Send the key only through the `apikey` header.
- Do not send `Authorization: Bearer`.
- Use temporary runtime environment only.
- Keep `CONFIRM_IMPORT` unset for dry-runs.
- Never use `--commit` without explicit approval.

## Production Promotion Bit Code

Files:

```text
scripts/confirm-production-promotion.ps1
scripts/build-sites-static.mjs
```

Production requires:

```text
PRODUCTION_PROMOTION_BIT_HASH
PRODUCTION_PROMOTION_BIT_CODE
PRODUCTION_PROMOTION_CONFIRM
```

How to store:

- Store only the SHA-256 hash of the Bit code in a secure environment/secret manager.
- Plaintext Bit code should live only in the approver's head or secure password manager.
- Plaintext is entered locally into a hidden prompt.
- Do not paste plaintext into Codex/chat.

## Current Pre-Production Security Limits

Current committed frontend:

```text
SUPABASE_ENABLED: false
```

So Pre-Production public version is still demo/static mode:

- data may be in browser `localStorage`
- demo accounts remain usable
- development PIN display is enabled in the Pre-Production bundle only
- not safe for real resident data

Reference:

```text
docs/PREPRODUCTION-SECURITY-REVIEW.md
docs/PROFILE-PIN-INTERFACE-ONBOARDING.md
```

## Production Safety

Before any real Production release:

1. Confirm Supabase backend/session is active.
2. Confirm no development PIN display.
3. Confirm demo accounts/password hints are removed or disabled.
4. Confirm no real data is stored in browser-only localStorage authority.
5. Confirm Staging has passed UAT and security review.
6. Require Bit-code approval.

