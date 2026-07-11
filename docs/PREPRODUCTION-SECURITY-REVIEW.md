# Pre-Production Security Review

Date: 2026-07-11

Target:

- Pre-Production URL: `https://juristic-care-v2-preprod.mitratiwa.chatgpt.site`
- Sites project: `appgprj_6a5275267d8481918257207f7d8df2f2`
- Access mode: public link

## Checks Performed

- Verified Pre-Production uses a separate Sites project from Production.
- Verified the Pre-Production build includes a visible `PRE-PRODUCTION`
  banner.
- Verified the Pre-Production bundle points to the Pre-Production Sites
  project id.
- Scanned the built `dist/` output for server Secret-Key markers:
  `sb_secret_`, `service_role`, `SUPABASE_SECRET_KEY`,
  `SUPABASE_SERVICE_ROLE_KEY`, and `Authorization: Bearer`.
- Verified production promotion runtime variables were not left in the shell.
- Verified Production bundle creation is blocked unless the Bit-code guard is
  satisfied.
- Verified baseline local tests still pass.

## Current Protections

- Pre-Production and Production are separate Sites projects.
- Production bundle creation requires a Bit-code hash and hidden prompt entry.
- Pre-Production has an environment banner to reduce accidental user confusion.
- The static worker adds:
  - `Content-Security-Policy`
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `X-Frame-Options: DENY`
  - `Permissions-Policy: camera=(), microphone=(), geolocation=()`
- The frontend config still has `SUPABASE_ENABLED: false`, so no Supabase
  Production backend is used by this deployment.
- No frontend Secret Key is present in the built Pre-Production output.

## Findings

| Severity | Finding | Evidence | Risk | Recommendation |
| --- | --- | --- | --- | --- |
| High | Pre-Production is public | Sites access mode is `public` | Anyone with the URL can open the tester app | Keep only fake/demo data in Pre-Production, or switch access back to owner-only/custom before using sensitive test data |
| High | Demo/local mode stores app data in browser `localStorage` | `config.js` has `SUPABASE_ENABLED: false`; app writes many `juristic*` keys to `localStorage` | Browser/device users can inspect or alter local demo data; no server authority protects it | Use fake data only until a separately approved Supabase cutover is complete |
| High | Demo login hints and demo credentials remain visible | Login failure copy mentions `ADMIN / STAFF-01 / STAFF-02 / A-0201` with `1234` | Public testers can enter admin/staff demo roles | Acceptable only for demo UAT; remove demo hints and seed passwords before any real-data release |
| Medium | Heavy dynamic HTML rendering | Many `innerHTML` / `insertAdjacentHTML` call sites | Escaping tests exist, but every future UI change must preserve escaping | Continue test coverage for user-controlled rendering and avoid raw HTML for new user input |
| Medium | External scripts/styles are allowed | Supabase client loads from `cdn.jsdelivr.net`; fonts load from Google | Supply-chain or CDN availability dependency | Pin external assets more tightly or vendor them before production hardening |
| Medium | Password-edit modal uses visible text input | `index.html` password modal uses `type="text"` | Admin password changes are shoulder-surfable in demo UI | Change to `type="password"` before real admin use |
| Low | No live HTTP header verification from this Windows shell | local `curl`/PowerShell TLS failed against the Sites URL | Header checks were validated from generated worker code, not a successful live response | Recheck live headers from a browser or another network before final production promotion |

## Bottom Line

Pre-Production is suitable for fake-data user acceptance testing. It is not
safe for real resident data while the app remains in public demo/localStorage
mode with demo credentials enabled.

