# QA Checklist

## Static Checks

```powershell
node --check app.js
node --check profiles.js
node --check supabase-client.js
```

## Encoding Check

Search for mojibake markers in source files:

```powershell
rg -n "â|à¸|à¹|Ã|Â|�" app.js profiles.js index.html styles.css config.js supabase-client.js docs supabase
```

Only intentional examples in documentation should match.

## Browser Smoke Test

- Open `http://127.0.0.1:4175/`
- Confirm default language is Thai.
- Confirm sidebar order and back-office group.
- Login demo user when Supabase is disabled.
- Confirm the interface picker appears after login.
- Choose `Compact` and confirm `#compactAppView` appears while `#appView` is hidden.
- For Admin, confirm compact tabs show overview, triage, review, and system.
- For Admin view-switch preview, choose Resident and confirm compact tabs show common, repair, and my room.
- For Resident, confirm profile/PIN gate completes before the interface picker appears.
- In Resident compact repair, confirm the Google Form action opens the configured `GOOGLE_FORM_URL` or shows the fallback toast.
- Create job.
- Assign job.
- Update status with attachment.
- Open Log and use filters.
- Open Permission Center and save permission.

## Supabase Smoke Test

- `SUPABASE_ENABLED=true` with real URL/key.
- Login via current UX.
- Upload attachment into private bucket.
- Resident cannot access another room's job/file.
- Staff can access assigned work.
- Admin can manage permission/sidebar/logs.
