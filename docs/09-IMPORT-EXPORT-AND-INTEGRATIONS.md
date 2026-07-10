# Import, Export, And Integrations

## CSV

Current CSV features:

- employee export/import
- resident room export/import
- finance mock export/import
- user deletion export support

Production direction:

- validate CSV in Edge Function
- restrict password export/import to Admin-only flows
- log every import/export action

## Google Forms

Production path:

- Google Forms sends payload to `supabase/functions/google-forms-ingest`
- function stores raw submission in `google_form_submissions`
- function creates raw/open job for `งานจากG-Form`

Frontend config:

- Set `window.JURISTIC_CONFIG.GOOGLE_FORM_URL` in `config.js` to the live resident repair form URL.
- Full mode `Google Forms` navigation opens the Google Forms entry point.
- Compact resident `แจ้งซ่อม` opens `GOOGLE_FORM_URL`; if it is blank, the app falls back to `https://docs.google.com/forms/` and shows a toast.

## Calendar

Current calendar is a mock/ICS export flow. A real Google Calendar integration should be added through a server-side integration, not by exposing private calendar credentials in frontend.
