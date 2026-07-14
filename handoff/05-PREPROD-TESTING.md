# Pre-Production Testing

URL:

```text
https://juristic-care-v2-preprod.mitratiwa.chatgpt.site
```

## Automated Baseline

Run:

```powershell
cd C:\Projects\juristic-care-V2
npm run check
npm test
npm run build:preprod
```

Expected:

```text
npm run check: pass
npm test: 72 tests, 57 pass, 0 fail, 15 todo
npm run build:preprod: pass
```

## Manual Test: Profile PIN Onboarding

Because Pre-Production is demo/fake-data mode, the built bundle shows the temporary PIN on screen.

1. Open Pre-Production URL.
2. Login with a demo account.
3. Confirm app does not enter dashboard immediately.
4. Confirm Choose Profile appears.
5. Confirm Owner profile appears first.
6. Add Tenant Profile if needed.
7. Add Resident Profile if needed.
8. Select a profile.
9. Confirm Verify PIN page appears.
10. Confirm PIN is 6 numeric digits.
11. Enter wrong PIN and confirm generic/clear error.
12. Enter correct PIN from development display.
13. Confirm Interface Design selection appears.
14. Choose Full Interface.
15. Confirm full sidebar/dashboard appears.
16. Open account menu `•••`.
17. Choose change interface mode.
18. Select Compact Interface.
19. Confirm compact app appears.
20. Logout, login again, confirm previous interface preference restores.

## Manual Test: Account Menu Flyout

1. Login and pass onboarding.
2. Click sidebar account `•••`.
3. Confirm menu opens to the side of sidebar, not below.
4. Click outside menu.
5. Confirm it closes.
6. Resize/mobile and confirm menu does not overflow screen.

## Known Test Limitation

The current Node test suite uses source-level regression checks, not browser E2E.

Reason:

- The project is a static vanilla JS app.
- Playwright is scaffolded but not the active mandatory baseline.

For stronger browser validation, next agent may add Playwright tests later.

