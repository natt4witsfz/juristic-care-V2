# 03 — Code Quality Audit

จำแนก: **[fact]** ตรวจแล้ว, **[likely]** น่าจะเป็นปัญหา, **[rec]** ข้อเสนอ ทุกข้อมีอ้างอิงไฟล์/บรรทัด

## A. โครงสร้างและขนาด

- **[fact]** `app.js` = 5,669 บรรทัด, ~330 KB เป็นไฟล์เดียว รวมทุก responsibility (I18N, seed data, state, business logic, render, event binding) — God-file
- **[fact]** ฟังก์ชันจำนวนมากยาวและปนความรับผิดชอบ เช่น `openJob` (บรรทัด 4394–4442) สร้าง HTML string ยาว + ผูก logic; `authenticateAppUser`/handler ยาว
- **[rec]** แยกเป็น modules: `i18n.js`, `state.js`, `workflow.js` (create/assign/update/verify), `render/*.js`, `api.js` เพื่อลด regression และทดสอบได้ ทำแบบค่อยเป็นค่อยไป (อย่ารื้อทีเดียว)

## B. Dead / duplicate / legacy code

- **[fact]** `supabase-schema.sql` (145 บรรทัด) ระบุตัวเองว่าเป็น legacy (บรรทัด 1–4) ซ้ำซ้อนกับ migration ใหม่ — เก็บไว้เพื่ออ้างอิงได้ แต่ควรย้ายเข้า `docs/legacy/` และทำหมายเหตุชัด
- **[fact]** มีสอง sync path (`queueRemoteSync` สำหรับ Apps Script + `queueSupabaseSync`) โดย Apps Script path (บรรทัด 1530–1588) เป็นของเฟสเก่า **[likely]** อาจกลายเป็น dead path เมื่อ Supabase-first สมบูรณ์
- **[fact]** ฟิลด์ legacy ใน `normalizeJob` (proposedAssignee/assignmentDeadline บรรทัด 902–906) — โค้ด migrate ข้อมูลเก่า เก็บไว้ได้แต่ควรมี comment ระบุ deprecation
- **[rec]** อย่าลบ code เพียงเพราะดูไม่ถูกใช้ จนกว่าจะยืนยัน (เช่น Apps Script path ยังถูกอ้างใน docs 09) — ทำ deprecation note ก่อน

## C. Hard-coded values / magic strings

- **[fact — CRITICAL]** รหัสผ่าน default `"1234"` ฝังใน seed users (บรรทัด 628–640) และผู้ใช้ใหม่ทุกคน (บรรทัด 5453, 2039, 1824)
- **[fact]** job id รูปแบบ hardcode `JC-260626-<seq>` (บรรทัด 1006) — เดือน/ปีตายตัว ควร generate จากวันที่จริง
- **[fact]** ค่างบการเงินเป็น mock hardcode (บรรทัด 1503–1510) และ finance import เป็น mock (บรรทัด 5601)
- **[fact]** วัน/เดือน/ปีปฏิทินเริ่มต้น hardcode (`selectedCalendarYear=2026`, บรรทัด 717) — mockup
- **[likely]** สถานะงานเป็น magic string กระจายทั่วไฟล์ (`"pending_inspection"`, `"waiting_owner_or_admin_verification"` ฯลฯ) ควรรวมเป็น const/enum เดียว

## D. Error handling

- **[fact]** การ sync ล้มเหลวถูกกลืนด้วย `console.warn` (บรรทัด 1572–1576, 1600–1605, 5399) ผู้ใช้เห็นแค่ toast บาง path — **[likely]** ข้อมูลอาจไม่ถูกบันทึกโดยผู้ใช้ไม่รู้ตัว
- **[fact]** `openJob`/`updateJobStatus` คืน error เป็น array ข้อความไทย hardcode (บรรทัด 1082–1102) ไม่มี error code มาตรฐาน

## E. Type safety / null handling

- **[fact]** เป็น vanilla JS ไม่มี type checking; ใช้ optional chaining + `||` fallback กระจาย (ดีระดับหนึ่ง) แต่ไม่มีการ validate schema ของ payload ที่รับจากภายนอก (Google Form/CSV/snapshot)
- **[likely]** `normalizeJob` เดาค่า default เยอะ (บรรทัด 878–934) ทำให้ข้อมูลผิดรูปถูกกลบแทนที่จะถูกปฏิเสธ — ควร validate ชัดที่ boundary

## F. Debug statements / TODO

- **[fact]** `console.log/warn/error` 11 จุด — ยอมรับได้ระดับ dev แต่ควรถอด/แทนด้วย logger ก่อน production (บาง log อาจมี PII)
- **[fact]** พบคำว่า mock/placeholder/TODO ~46 แห่ง (grep) ส่วนใหญ่คือ mockup ที่ตั้งใจ (ปฏิทิน/งบ) ควรทำ backlog ให้ชัดว่าอันไหน "ยังไม่ทำ" vs "ตั้งใจเป็น demo"

## G. Unused imports / dependencies

- **[fact]** ไม่มี package dependency (โหลด Supabase จาก CDN) จึงไม่มี unused dep ในเชิง package
- **[fact]** โหลด `@supabase/supabase-js` จาก CDN เสมอแม้ Supabase ปิด (`index.html` บรรทัด 567) — **[likely]** เพิ่มเวลาโหลดโดยไม่จำเป็นในโหมด demo; พิจารณา lazy load เมื่อ `SUPABASE_ENABLED`

## H. Consistency

- **[fact]** โค้ดสอดคล้องกับกฎใน `WORK-LOCK-NO-UX-UI.md`: identifier เป็นภาษาอังกฤษ, ข้อความผู้ใช้ผ่าน I18N ส่วนใหญ่ **[likely]** แต่มีข้อความไทย hardcode ในบาง render (เช่น modal งาน บรรทัด 4322–4353) ที่ไม่ผ่าน `t()` — ขัดกับกฎ bilingual เอง

## จุดแข็งด้านคุณภาพที่ควรรักษาไว้

- มีฟังก์ชัน `esc()` (บรรทัด 1703) และใช้ครบในหน้า resident/team — ทีมเข้าใจ XSS แล้ว เพียงแต่ลืมใช้ที่หน้างาน (ดู `04`)
- แยกฟังก์ชัน workflow กลาง (`createJob`, `assignJob`, `updateJobStatus`, `verifyCompletion`, `canViewJob` ฯลฯ) เตรียมย้าย backend ได้ — โครงคิดมาดี
- schema/RLS/Edge Functions เขียนเป็นระเบียบ มี security-definer + audit log

## สรุปลำดับความสำคัญด้าน quality

1. แก้ XSS (ดู `04`) — เร่งด่วน
2. เอา default password `1234` + plaintext ออก
3. รวม status enum + validate boundary
4. แยกไฟล์ God-file แบบค่อยเป็นค่อยไป (ไม่เร่ง, ทำหลังปิดช่อง security)
