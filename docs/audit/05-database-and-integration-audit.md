# 05 — Database & Integration Audit

## D. ฐานข้อมูลและ Data Model (Supabase migration)

อ้างอิง `supabase/migrations/202607090001_full_supabase_schema.sql`

### จุดแข็ง [fact]
- Primary keys ครบทุกตาราง, ใช้ `uuid default gen_random_uuid()` เหมาะสม
- Foreign keys + on delete rules ระบุชัด (เช่น `job_close_pins.job_id → jobs on delete cascade`, บรรทัด 77)
- Index บนคอลัมน์ที่ query บ่อย: `app_users(auth_user_id)`, `jobs(room_id/assignee_id/status)`, `audit_logs(created_at desc)`, `job_timeline(job_id, created_at desc)` (บรรทัด 199–204)
- Audit fields `created_at`/`updated_at` มีเกือบทุกตาราง ใช้ `timestamptz` (timezone-aware) — ถูกต้อง
- `audit_logs` มี policy กัน update/delete (บรรทัด 506–510) = immutable ระดับ client — ดีมาก
- PIN ทั้งลูกบ้านและปิดงานเก็บเป็น `crypt(..., gen_salt('bf'))` (bcrypt) — ถูกต้อง

### ปัญหา / ช่องว่าง

| ID | รุนแรง | ประเด็น | หลักฐาน |
| --- | --- | --- | --- |
| DB-01 | High | ตาราง PII (`resident_people`, `resident_cars`, `room_profiles`) เปิด RLS แต่ **ไม่มี policy** และ **ไม่มี RPC อ่าน** → เข้าถึงได้เฉพาะผ่าน snapshot bridge (ไม่กรอง) | บรรทัด 460–475 เปิด RLS; ไม่มี `create policy` สำหรับตารางเหล่านี้ |
| DB-02 | High | `jobs.payload` เก็บทั้ง object เป็น JSONB ทำให้ column ที่เป็น relational (status/room_id) กับ payload อาจไม่ตรงกัน (dual source of truth) | บรรทัด 55–74; RPC update ทั้ง column และ payload พร้อมกัน |
| DB-03 | Medium | `update_job_status` เขียน `next_update_date = nullif(...)::date` แม้ payload ไม่ส่งมา → อาจ **ล้างค่าเดิมเป็น null** โดยไม่ตั้งใจ | บรรทัด 401 |
| DB-04 | Medium | ไม่มี soft delete / สถานะ transition constraint ใน DB — เปลี่ยน status เป็นค่าใดก็ได้ | ไม่มี check/trigger บน `jobs.status` |
| DB-05 | Medium | ไม่มี unique constraint กันงานซ้ำจาก 1 Google Form submission ระดับ business (idempotency พึ่ง `external_id` unique เท่านั้น แต่ job id generate จาก timestamp) | `google-forms-ingest` 43 job id = timestamp-based |
| DB-06 | Low | `rooms.common_fee_status` เป็น text ไม่มี check constraint | บรรทัด 13 |
| DB-07 | Low | `grant ... on all tables ... to authenticated` (บรรทัด 528) กว้าง — พึ่ง RLS ล้วน ถ้าลืม policy บนตารางใหม่จะ deny (ดี) แต่ถ้าเผลอเพิ่ม policy หลวมจะเปิดกว้างทันที | บรรทัด 527–529 |

### สถานะ integrity ที่ตรวจแล้ว
- **[fact]** referential integrity ดี (FK ครบ)
- **[likely]** N+1 / unbounded query: `get_app_bootstrap` (บรรทัด 437) ดึง jobs/logs/announcements ทั้งหมดในครั้งเดียวโดยไม่มี pagination — โตขึ้นตามเวลา จะช้า
- **[fact]** backup/restore: ไม่มี config; พึ่ง Supabase managed backup (ต้องยืนยันแผน)

### Row Level Security (สรุปการตรวจ)
- policy ที่มี: `rooms`, `app_users` (staff เห็นหมด), `jobs` (ผ่าน `can_read_job`), `audit_logs`, `announcements`, `permissions`, `sidebar_preferences`, `storage.objects`
- **[fact]** `app_users_select` ให้ staff เห็นทุก user รวมคอลัมน์อ่อนไหว (permissions ฯลฯ) — กว้างกว่าที่ควร ควรทำ view ตัดคอลัมน์
- **[fact]** `is_admin_account()` นับ `is_co_admin` เป็น admin (บรรทัด 241) — ต้องยืนยันว่าตรงเจตนา (Co-Admin ควรมีสิทธิ์น้อยกว่า admin ในบางเรื่อง เช่นเห็นรหัสผ่าน)

## G. External Integrations

### Google Form → Edge Function `google-forms-ingest`
- **[fact]** auth: shared secret header `x-ingest-secret` **แต่ข้ามถ้า secret ว่าง** (บรรทัด 20–22) → ถ้าลืมตั้ง env = เปิด public
- **[fact]** ใช้ service_role ทั้งหมด (บรรทัด 28) เขียน `google_form_submissions` + `jobs` + `audit_logs`
- **[fact]** idempotency: upsert ด้วย `external_id` (บรรทัด 34) — ดี แต่ job id generate จาก `Date.now()` (บรรทัด 43) ทำให้ retry ที่ไม่มี external_id อาจสร้างงานซ้ำ
- **[likely]** payload ดิบถูกส่งเข้า `jobPayload` โดยไม่ validate/sanitize → ต้นเหตุ SEC-01 (XSS)
- **failure mode**: ถ้า job insert ล้มเหลว submission ถูกทำเครื่องหมาย new; ไม่มี retry/backoff

### Edge Function `admin-users`
- **[fact]** ตรวจ caller เป็น admin/co_admin ก่อน (บรรทัด 39–45) — ดี
- **[fact — High]** action `create` ตั้ง `password` default `"1234"` ถ้าไม่ส่งมา (บรรทัด 51) และ `email_confirm: true` — สืบทอดปัญหา SEC-02
- **[fact]** `reset-password` list users ทั้งหมดเพื่อหา target (บรรทัด 90) — ไม่ scale เมื่อ user เยอะ (Supabase listUsers pagination)

### Edge Function `secure-file-access`
- **[fact]** ออกแบบดี: ตรวจสิทธิ์ผ่าน `can_access_storage_object` ด้วย user client ก่อน ค่อยออก signed URL ด้วย service client (บรรทัด 36–45), clamp expiresIn 60–3600s (บรรทัด 33) — เป็น pattern ที่ถูกต้อง

### Google Apps Script (เส้นทางเก่า)
- **[fact]** `remoteRequest` POST ไป `APPS_SCRIPT_URL` เป็น text/plain (บรรทัด 1532–1536) ส่ง snapshot ทั้งก้อน
- **[likely]** ถ้า Apps Script `/exec` ตั้ง "anyone can access" = endpoint public เขียน/อ่านข้อมูลทั้งระบบได้ **[ข้อมูลที่ยังขาด]** ต้องตรวจการตั้งค่า deployment ของ Apps Script จริง (อยู่นอก repo)

### Google Calendar / Drive / Sheet
- **[fact]** Calendar เป็น mockup (สร้าง .ics ฝั่ง client, บรรทัด 3066) ยังไม่ต่อ API
- **[ข้อมูลที่ยังขาด]** OAuth scopes / service-account / ownership ของไฟล์ Drive/Sheet ตรวจไม่ได้จาก repo

### LINE OA / Web Push
- **[fact]** ไม่มีในโค้ด — ยังไม่ implement

## หากใช้ Supabase (สรุปสิ่งที่ต้องปิดก่อนเปิดใช้จริง)
1. เพิ่ม policy หรือ RPC สำหรับ `resident_people`/`resident_cars`/`room_profiles` และเลิกพึ่ง snapshot bridge
2. บังคับ `x-ingest-secret`/HMAC เสมอใน webhook
3. ใส่ PIN/transition check ใน `update_job_status`/`verify_job_completion`
4. จำกัด CORS origin ใน Edge Functions
5. เปลี่ยน default password ออกจาก `1234`
