# 04 — Security Audit

จำแนกความรุนแรง: Critical / High / Medium / Low ทุกข้อมีหลักฐาน ไฟล์/บรรทัด ไม่มีการเปิดเผยค่า secret ใด ๆ

## สรุป Secret Scan (Phase 0)

- **[fact]** `config.js` ค่าทั้งหมดว่าง (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_FORM_URL` = `""`) — **ไม่มี secret จริงถูก commit ในไฟล์นี้**
- **[fact]** ไม่พบ pattern secret จริง (AIza…, sk-…, eyJhb… JWT, service_role) ในไฟล์ tracked
- **[fact — Medium]** `DEPLOYED-URLS.md` เปิดเผย endpoint ระบบจริงของ pilot: Apps Script exec URL, Google Sheet ID, Google Drive folder ID, Apps Script project (บรรทัด 5–17) — ไม่ใช่ secret โดยตรง แต่เป็น attack surface (โดยเฉพาะ Apps Script `/exec` ถ้าไม่ตรวจสิทธิ์) ควรถือเป็นข้อมูลอ่อนไหว
- **[ข้อมูลที่ยังขาด]** ตรวจ git history ไม่ได้ (โฟลเดอร์ไม่ใช่ git repo) — ยังไม่ยืนยันว่าเคยมี key ถูก commit แล้วลบหรือไม่ ต้องสแกน history บน GitHub จริง (แนะนำ `gitleaks`/`trufflehog`)

## ตารางช่องโหว่หลัก

| ID | รุนแรง | ช่องโหว่ | หลักฐาน | คำแนะนำ |
| --- | --- | --- | --- | --- |
| SEC-01 | **Critical** | Stored XSS ผ่านฟิลด์งาน | `app.js` 3276, 4413–4427 (title/roomNo/contactName/contactPhone/note เข้า innerHTML ไม่ผ่าน esc); ป้อนได้จาก `google-forms-ingest` payload ดิบ | ใช้ `esc()` ทุกฟิลด์ที่มาจากผู้ใช้/ภายนอกก่อนเข้า DOM |
| SEC-02 | **Critical** | รหัสผ่าน plaintext + default `1234` ทุกบัญชี | `app.js` 628–640, 5453, 5475; CSV export รหัสผ่าน plaintext 1764–1770 | สุ่มรหัสต่อบัญชี, บังคับเปลี่ยนครั้งแรก, ไม่ export รหัสผ่าน |
| SEC-03 | **Critical** | Authorization ตัดสินฝั่ง client ล้วน | `app.js` 826–851 อ่านจาก `currentUser`/localStorage แก้ได้ใน DevTools | บังคับสิทธิ์จริงที่ RLS/RPC ฝั่งเซิร์ฟเวอร์ |
| SEC-04 | **High** | Snapshot bridge ลบล้าง RLS + รั่ว PII | migration 424–458 (`save_client_snapshot`/`get_app_bootstrap` คืน state ทั้งก้อนให้ staff ทุกคน) | เลิก snapshot bridge, เปลี่ยนเป็น RPC/endpoint ต่อ entity ที่กรองตามบทบาท |
| SEC-05 | **High** | Stored XSS ผ่านชื่อโปรไฟล์ลูกบ้าน | `profiles.js` 89, 151 (`p.name`/`profile.name` เข้า innerHTML ไม่ escape) | escape ชื่อ, จำกัดอักขระ |
| SEC-06 | **High** | CORS `*` บน Edge Functions ทั้งหมด | `admin-users` 4, `google-forms-ingest` 5, `secure-file-access` 4 | จำกัด origin เป็นโดเมนแอปจริง |
| SEC-07 | **High** | ไม่มี PIN check ในเส้นทางปิดงานฝั่งเซิร์ฟเวอร์ | migration `update_job_status` 392–408 ไม่แตะ `job_close_pins` | บังคับ PIN/สถานะ transition ใน RPC (ดู `06`) |
| SEC-08 | **Medium** | ไม่มี webhook signature verification ที่แข็งแรง | `google-forms-ingest` 20–22 ใช้แค่ shared secret header และ **ข้ามการตรวจถ้า secret ว่าง** (`if (expectedSecret && ...)`) | บังคับ secret เสมอ, ปฏิเสธถ้าไม่ตั้งค่า, เพิ่ม HMAC + timestamp กัน replay |
| SEC-09 | **Medium** | `jobs_insert` policy หลวม | migration 489–491 อนุญาต insert ถ้ามี app_user id ใด ๆ | จำกัด insert ให้เฉพาะ staff หรือ reporter ห้องตัวเอง; ตรวจ status เริ่มต้น |
| SEC-10 | **Medium** | ไม่มี rate limiting / brute-force protection | ไม่มีในโค้ด (login, PIN pad `profiles.js` 167) | เพิ่ม throttle/lockout ที่ Supabase Auth + PIN attempts |
| SEC-11 | **Medium** | ไม่มี security headers / CSP | ไม่มี meta CSP ใน `index.html`; โหลด script จาก CDN | เพิ่ม CSP, X-Content-Type-Options, ตั้งที่ hosting |
| SEC-12 | **Low** | Watermark timestamp จาก client แก้ได้ | `app.js` 5374, 5415 (`imageStampText` ใช้เวลา client) | ประทับ server-side หรือใช้เวลา server สำหรับหลักฐาน |
| SEC-13 | **Low** | `print`/`window.open` ฝัง HTML ที่มี field ผ่าน esc บางส่วน | `printJobPdf` 1458 (issueDescription ผ่าน esc แต่ตรวจซ้ำทุก field) | ตรวจว่า escape ครบทุก interpolation ในหน้าพิมพ์ |

## รายละเอียด SEC-01 (Stored XSS) — verified

`jobRow` (บรรทัด 3276) แทรกเข้า innerHTML โดยตรง:
```
<span>${job.roomNo}...</span><span>${job.contactName || "-"} ${job.contactPhone || ""}</span>
```
`openJob` (บรรทัด 4417–4427): `roomNo`, `contactName`, `contactPhone`, `note` เข้า `<strong>` ไม่ผ่าน `esc()` และ `getText(job.title)` ที่ modalTitle/หัวการ์ดก็ raw

เส้นทางป้อนข้อมูล: `google-forms-ingest` (บรรทัด 44–59) map `payload.description/room/contact` ดิบลง job.payload → เมื่อ staff เปิดดูงาน สคริปต์จาก payload รันในเซสชันเจ้าหน้าที่/แอดมิน = privilege ที่สูงที่สุดในระบบ ความเสี่ยงจึงเป็น **Critical**

## Threat Model (แบบ lightweight)

**Assets**: ข้อมูลลูกบ้าน (ชื่อ/เบอร์/เลขห้อง/ทะเบียนรถ/สถานะค่าส่วนกลาง), รูปหลักฐานงาน, บัญชีผู้ใช้+รหัสผ่าน, audit log, PIN ปิดงาน

**Actors**: แอดมิน, Co-Admin, เจ้าหน้าที่/ช่าง, กรรมการ, ลูกบ้าน, ผู้แจ้งภายนอกผ่าน Google Form (untrusted), ผู้โจมตีทั่วไป

**Trust boundaries**: browser client ↔ Supabase (RLS/RPC) ↔ Edge Functions (service_role) ↔ Google (Form/Sheet/Drive)

**Entry points**: หน้า login, Google Form webhook, CSV import (team/resident), file upload, snapshot sync

**Abuse cases → Control ปัจจุบัน → Control ที่ขาด**
- ผู้แจ้งภายนอกฝัง XSS ผ่านฟอร์ม → *ไม่มี* → ต้อง escape + sanitize (SEC-01)
- ผู้ใช้ทั่วไปยกระดับเป็น admin → *ไม่มีฝั่ง client* → RLS/RPC จริง (SEC-03)
- Staff คนหนึ่งดึง/แก้ข้อมูลทั้งอาคาร → snapshot bridge เปิดช่อง → เลิก bridge (SEC-04)
- ช่างปิดงานโดยไม่มี PIN → client บล็อกได้ แต่ RPC ไม่ → เพิ่ม server check (SEC-07)
- Brute-force PIN/รหัสผ่าน → *ไม่มี* → rate limit (SEC-10)
- Replay webhook → *ไม่มี* → HMAC + timestamp + idempotency (SEC-08)

## ความเป็นส่วนตัว (Privacy) — ไม่มีข้อสรุปทางกฎหมาย

- **[fact]** ระบบเก็บ PII: ชื่อ-นามสกุล, ชื่อเล่น, เบอร์โทร, เลขห้อง, ทะเบียนรถ, สถานะค่าส่วนกลาง, รูปถ่ายงาน (อาจมีใบหน้า/ภายในห้อง)
- **[likely]** ไม่มีนโยบาย retention/deletion/consent, ไม่มีการ redact PII ใน log, EXIF ของรูปไม่ถูกลบ (อัปโหลดผ่าน canvas re-encode จะลบ EXIF ของรูปที่ผ่าน canvas — แต่ path ที่ไม่ใช่รูป/ไม่ผ่าน canvas ไม่ลบ)
- **[rec]** ทำ data minimization (เก็บเท่าที่จำเป็น), retention policy, สิทธิ์ลบข้อมูลลูกบ้าน, redact เบอร์/ชื่อใน log ก่อนใช้ข้อมูลจริง — โปรดปรึกษาผู้เชี่ยวชาญ PDPA ก่อน go-live

## Dependency / supply chain

- **[fact]** โหลด `@supabase/supabase-js@2` และ Google Fonts จาก CDN โดยไม่มี SRI (subresource integrity) — **[rec]** เพิ่ม SRI hash หรือ self-host เพื่อกัน CDN ถูกแก้
