# 08 — Testing Strategy & QA

## สถานะปัจจุบัน [fact]
- **ไม่มี test ใด ๆ** ในโปรเจกต์ (ไม่มี unit/integration/e2e, ไม่มี test framework, ไม่มี CI)
- มีเพียง manual verification checklist ใน `WORK-LOCK-NO-UX-UI.md` (บรรทัด 117–128) และ `docs/10-QA-CHECKLIST.md`
- Coverage โดยประมาณ: **0%**

## กลยุทธ์ทดสอบที่แนะนำ (เรียงตามคุ้มค่า)

### ชั้นที่ 1 — Smoke & static (ทำได้ทันที, ต้นทุนต่ำ)
- `node --check` ทุกไฟล์ JS (มีอยู่แล้ว — ผูกเข้า CI)
- ESLint + `deno check` สำหรับ Edge Functions
- Smoke: เปิดหน้าเว็บ headless (Playwright) แล้วตรวจว่า login ADMIN/1234 เข้าได้และ dashboard render

### ชั้นที่ 2 — Unit tests (business logic ล้วน — คุ้มสุด)
แยกฟังก์ชัน workflow ออกเป็น module ที่ import ได้ แล้วทดสอบ:
- `validateStatusUpdate` — ทุกสถานะ, กรณีรูป 0/1/3/4 ใบ, PIN ถูก/ผิด, noPin
- `checkScheduleConflict` — เวลาซ้อน/ไม่ซ้อน/คนละวัน
- `normalizeStatus`/`statusLabelNew` — mapping ครบ
- `canViewJob`/`canUpdateJob`/`canSeeClosePin`/`canVerifyCompletion` — ทุกบทบาท
- helper วันที่ Asia/Bangkok (หลังแก้ timezone)

### ชั้นที่ 3 — Database / RLS / RPC tests (เมื่อเปิด Supabase)
รันบน Supabase project ทดสอบแยก (ไม่ใช่ production):
- authorization: resident เห็นเฉพาะงานห้องตัวเอง; staff เห็นเฉพาะงานที่รับ
- IDOR: resident เรียก `can_read_job` ของห้องอื่น → false
- workflow: `update_job_status` completed โดยไม่มี PIN → ต้องไม่ completed (หลังแก้)
- audit immutability: พยายาม update/delete `audit_logs` → ถูกปฏิเสธ
- storage: ขอ signed URL ไฟล์ห้องอื่นในฐานะ resident → 403

### ชั้นที่ 4 — Integration / webhook
- `google-forms-ingest`: ไม่มี secret → 403; ส่ง external_id เดิมซ้ำ → 1 งาน (idempotency); payload มี `<script>` → ต้องไม่ execute เมื่อ render (หลังแก้ escape)

### ชั้นที่ 5 — E2E (Playwright) เส้นทางหลัก
- สร้างงาน → มอบหมาย → ช่างอัปเดต → ปิดด้วย PIN → completed
- fallback ไม่มี PIN → pending_inspection → admin verify → completed
- ลูกบ้าน login → profile PIN → เห็นเฉพาะห้องตัวเอง

## Acceptance Test Matrix (workflow หลักคอนโด)

| # | Scenario | Given | When | Then |
| --- | --- | --- | --- | --- |
| AT-1 | สร้างงาน+มอบหมาย | admin login | สร้างงาน เลือกช่าง | งานเข้า "งานของฉัน" ช่างทันที, timeline มี created+assigned |
| AT-2 | เวลาซ้อน | ช่างมีงาน 10–11 น. | มอบงานใหม่ 10:30 | ระบบเตือน confirm ก่อนสร้าง |
| AT-3 | ปิดด้วย PIN | งาน received | เลือก completed + PIN ถูก | status = completed, completedAt ตั้ง |
| AT-4 | PIN ผิด | งาน received | completed + PIN ผิด | error "PIN ไม่ถูกต้อง", ไม่ปิด |
| AT-5 | ไม่มี PIN | ลูกบ้านไม่อยู่ | completed + noPin + เหตุผล + รูป | pending_inspection + waiting_verification |
| AT-6 | ยืนยันปิด | AT-5 แล้ว | admin กดยืนยัน | completed |
| AT-7 | required รูป | งาน received | completed ไม่มีรูป | ถูกปฏิเสธ (ทั้ง client และ server) |
| AT-8 | สิทธิ์ลูกบ้าน | resident A-0201 | เปิดงานห้อง B | เข้าไม่ได้ / มองไม่เห็น |
| AT-9 | timezone | เครื่อง UTC 18:00 | สร้างงาน "วันนี้" | วันที่ = วันไทยที่ถูกต้อง |
| AT-10 | idempotency | webhook external_id X | ส่งซ้ำ 2 ครั้ง | 1 งาน |
| AT-11 | XSS | ฟอร์มมี `<script>` | staff เปิดงาน | ข้อความแสดงเป็น text ไม่ execute |
| AT-12 | audit immutable | มี audit log | พยายามลบ | ถูกปฏิเสธ |

## เครื่องมือแนะนำ
- Unit: **Vitest** (เบา, ไม่ต้อง build) หรือ `node:test`
- E2E/smoke: **Playwright**
- DB/RLS: pgTAP หรือ script Node เรียก Supabase ด้วย 2 บทบาท
- CI: GitHub Actions (lint + check + unit + smoke) — repo อยู่ GitHub อยู่แล้ว

## Regression suite ขั้นต่ำก่อน merge
`node --check` + unit ของ `validateStatusUpdate`/`checkScheduleConflict`/permission + smoke login = ประตูก่อน merge ทุกครั้ง
