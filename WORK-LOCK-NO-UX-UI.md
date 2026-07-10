# Juristic Care Work Lock

This file is the continuation note for future Codex work on this project.

## Hard Rule

- Do not change UX/UI layout, styling, interaction patterns, or screen structure unless the user explicitly asks for a UX/UI change.
- Keep edits scoped to the requested behavior.
- Preserve existing user changes. Do not revert unrelated work.

## Language And Encoding Rules

- Source code must use English for identifiers, comments, state keys, helper names, and internal labels.
- User-facing text must be handled through the bilingual language system wherever practical.
- Thai is the default display language.
- English is the secondary display language.
- Keep all project text files encoded as UTF-8.
- Do not rewrite UTF-8 files through PowerShell pipelines or commands that may reinterpret Thai text as Windows-1252.
- If corrupted text appears, such as `â`, `Ã`, `Â`, `à¸`, `à¹`, or `�`, fix encoding before making feature edits.

## Bilingual System

- Main translation dictionaries live in `app.js` under `I18N.th` and `I18N.en`.
- The default language must remain:

```js
let currentLang = localStorage.getItem("juristicLang") || "th";
```

- Static DOM labels should use `data-i18n` where practical.
- Dynamic labels should call `t("translation.key")` instead of hard-coding Thai or English directly in rendering logic.
- New user-facing strings should be added to both Thai and English dictionaries before use.

## Current App Shape

- Static vanilla web app.
- Production path is Supabase-first.
- LocalStorage is demo/dev fallback only when `SUPABASE_ENABLED=false`.
- Main files:
  - `index.html`
  - `styles.css`
  - `app.js`
  - `profiles.js`
  - `supabase-client.js`
  - `config.js`
  - `supabase-schema.sql`

## Supabase Production Rules

- Frontend may use only `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- Never put a Supabase `service_role` key in frontend files.
- Service role belongs only in Edge Functions.
- All production tables must have RLS enabled.
- File buckets must stay private:
  - `job-attachments`
  - `announcement-files`
  - `profile-images`
- Critical workflow writes should move toward RPC/Edge Function calls instead of direct client table writes.
- Documentation starts at `docs/00-DOCUMENTATION-INDEX.md`.

## Current Sidebar Defaults

Default sidebar order:

1. Google Forms
2. ภาพรวม
3. งานของฉัน
4. งานส่วนกลาง
5. งานของลูกบ้าน
6. งบการเงิน
7. ปฏิทิน
8. งานจากG-Form
9. งานของทีมงาน
10. ห้องของฉัน
11. ระบบหลังบ้าน

Back-office group contains:

1. พนักงานและบริษัทคู่สัญญา
2. ลูกบ้าน
3. Organization Chart
4. ประกาศ
5. สิทธิ์การใช้งาน
6. Log

All sidebar items, including grouped items, must stay connected to the permission center.

## Recent Functional Requirements

- Log combines admin, staff, and resident activity.
- Log filters support date range, department multi-select, and person/room multi-select with search.
- Department/person filter options should behave like Excel-style dropdown filters.
- Staff work view is grouped under `งานของทีมงาน`.
- Staff work main filter must stay at the top and use a multi-select dropdown.
- `Pool งานกลาง` was renamed to `งานจากG-Form`.
- Google Forms is a sidebar item and must appear in permission settings.
- Admin users have a view-switching function for testing authority and UX/UI views by department.
- Logout belongs in the profile three-dot menu, not as a sidebar item.
- Compact mode is an explicitly approved second interface. It must stay separate from the full sidebar UI.
- Interface picker must appear every time after successful login/profile/PIN flow.
- Resident compact tabs are common work status, Google Form repair, and my room.
- Admin/Co-Admin compact mode must exist, but Admin keeps broader system/view-switch tools than Co-Admin.
- Resident compact repair must use the configured Google Form URL, not a separate compact repair form.

## Dashboard Status Colors

Use these colors for the incident overview bar/status colors:

| Status | Background | Text |
| --- | --- | --- |
| งานใหม่ | `#DBEAFE` | `#1D4ED8` |
| กำลังดำเนินการ | `#FEF3C7` | `#B45309` |
| แก้ไขเรียบร้อย | `#DCFCE7` | `#15803D` |

## Verification Checklist

Run these checks after changes:

```powershell
node --check "C:\Users\natta\OneDrive\Desktop\Claude\O83\Juristic Care\app.js"
```

- Open `http://127.0.0.1:4175/` in the browser.
- Confirm Thai text displays normally with no mojibake.
- Confirm the default UI language is Thai.
- Confirm the sidebar order and back-office group are correct.
- Confirm permission settings include every sidebar item.
- Confirm no corrupted text markers are visible in the app.
