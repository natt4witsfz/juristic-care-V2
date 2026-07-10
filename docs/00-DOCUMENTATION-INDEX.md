# Documentation Index

เอกสารชุดนี้คือคู่มือกำกับ WebApp `Juristic Care` สำหรับพัฒนา ทดสอบ และย้ายขึ้น Supabase โดยไม่เปลี่ยน UX/UI เดิมโดยไม่จำเป็น

## Recommended Reading Order

1. `01-WEBAPP-OVERVIEW.md` - ภาพรวมระบบและโมดูลหลัก
2. `02-FUNCTION-MAP.md` - แผนที่ฟังก์ชันและความเชื่อมโยง
3. `03-DATA-STATE-STORAGE.md` - state, storage keys, data ownership
4. `04-WORK-ORDER-FLOW.md` - flow งานแจ้งซ่อม/งานทีมงาน
5. `05-PERMISSIONS-SIDEBAR.md` - สิทธิ์และ sidebar
6. `06-LOG-AUDIT.md` - Log และ audit trail
7. `07-I18N-ENCODING.md` - ภาษาและ encoding
8. `08-UI-VIEWS-AND-NAVIGATION.md` - view/navigation mapping
9. `09-IMPORT-EXPORT-AND-INTEGRATIONS.md` - CSV, Calendar, Google Forms
10. `10-QA-CHECKLIST.md` - checklist ทดสอบ
11. `11-SUPABASE-ARCHITECTURE.md` - Supabase architecture
12. `12-SECURITY-MODEL.md` - security/RLS model
13. `13-STORAGE-UPLOADS.md` - private file upload
14. `14-DEPLOY-RUNBOOK.md` - deploy runbook
15. `15-DATA-MIGRATION-CHECKLIST.md` - checklist ย้ายข้อมูล
16. `16-GAP-REVIEW-AND-ROUTINE-WORK-PLAN.md` - gap review และแผน Routine Work / PM / Time Block (proposal)

## Focused Work-System Docs

- `17-WORK-ASSIGNMENT-DETAIL-UX-SPEC.md` - current-state spec for work assignment, job detail, assignee workflow, and related UX/UI risks.

## Source Of Truth

- UI runtime: `index.html`, `styles.css`, `app.js`, `profiles.js`
- Environment config: `config.js`
- Supabase frontend adapter: `supabase-client.js`
- Supabase database/security: `supabase/migrations/202607090001_full_supabase_schema.sql`
- Supabase server-only actions: `supabase/functions/*`

## Hard Rules

- Do not change UX/UI unless the user explicitly requests it.
- Default display language is Thai.
- New code identifiers, comments, and internal keys must be English.
- Keep files UTF-8.
- Do not put Supabase `service_role` keys in frontend files.
