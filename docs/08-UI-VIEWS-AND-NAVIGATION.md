# UI Views And Navigation

## View System

Navigation buttons use `data-view`. `navigate(view)` activates the matching view and renders relevant content.

Important views:

- `dashboard`
- `googleForms`
- `myjobs`
- `commonWork`
- `residentWork`
- `finance`
- `calendar`
- `pool`
- `staffJobs`
- `roomjobs`
- `team`
- `residents`
- `organization`
- `backhouse`
- `permissions`
- `logs`

## Rendering Pattern

- `renderAll()` refreshes global UI.
- Specific render functions update their own panels.
- `ensure*View()` functions create late-added sections without changing the original shell.

## Interface Picker And Compact Mode

After successful login, and after resident profile/PIN verification, `showApp(user)` opens the interface picker every time.

- `Full` keeps the original sidebar/full application unchanged.
- `Compact` shows a separate `#compactAppView` shell and hides `#appView`.
- Users can return to full mode with the compact top-bar `Full` button.
- Compact mode uses the same `jobs`, permissions, language state, auth session, and Supabase/local fallback data as the full UI.

Compact tabs are role-aware:

- Resident: common work status, repair Google Form, my room.
- Admin: overview, triage, review, back-office/system shortcuts.
- Co-Admin: overview, triage, review, permitted team/back-office shortcuts.
- Juristic staff: overview, triage, follow-up.
- Other staff: today, my jobs.

Resident repair in compact mode does not create a separate repair form. It opens the configured Google Form URL.

## UX Rule

Do not move sidebar, modals, filters, buttons, or layout unless explicitly requested. Backend migration must preserve the existing UX.
