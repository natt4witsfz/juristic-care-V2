# 06 — Business Workflow Gap Analysis

เทียบ implementation กับกฎ workflow ที่ผู้ว่าจ้างกำหนด แต่ละข้อ: current / expected / gap / risk / affected files / correction / acceptance test

## 1. Task lifecycle (New → In Progress → Inspecting → Completed → Issue/Rework)

- **Current [fact]**: มีสถานะครบและมากกว่านั้น (`open`, `received`, `pending_inspection`, `inspected_waiting_repair`, `repaired_follow_up`, `temporary_waiting_parts`, `completed`, `rejected` + subStatus `waiting_owner_or_admin_verification`) — `app.js` 856–863, README 59
- **Expected**: ครบตามนี้ ✔
- **Gap**: ไม่มี state machine ที่บังคับลำดับ transition — ตั้ง status ข้ามขั้นได้ทั้ง client และ DB
- **Risk**: Medium — ข้อมูลสถานะไม่สอดคล้อง
- **Affected**: `app.js` `updateJobStatus` (1104); migration `update_job_status` (392)
- **Correction**: นิยาม allowed transitions ตารางเดียว บังคับทั้ง client และ RPC
- **Acceptance test**: พยายามเปลี่ยน `open → completed` ตรง ๆ ต้องถูกปฏิเสธ

## 2. ปิดงานต้องไม่ final เพราะกดปุ่มเดียว (ต้องอนุมัติ)

- **Current [fact]**: ฝั่ง client — ถ้ามี PIN ถูกต้องปิดได้เลย; ถ้าไม่มี PIN ต้องผ่านการยืนยันโดยผู้มีสิทธิ์ (`updateJobStatus` 1111–1125, `verifyCompletion` 1151)
- **Gap [CRITICAL]**: ฝั่งเซิร์ฟเวอร์ `update_job_status` ตั้ง `status='completed'` ได้โดย **ไม่ตรวจ PIN และไม่ตรวจว่าใครมีสิทธิ์ปิด** (แค่ `can_update_job` ซึ่งรวม assignee) → ช่างปิดงานเองผ่าน RPC ได้
- **Risk**: Critical — กฎธุรกิจหลักถูกข้ามเมื่อเปิด Supabase
- **Affected**: migration 392–422
- **Correction**: ใน `update_job_status` ถ้า target = completed ต้องตรวจ `crypt(pin) = job_close_pins.pin_hash` มิฉะนั้นบังคับเข้า `pending_inspection/waiting_verification`; `verify_job_completion` ต้องจำกัดเฉพาะ admin/ผู้มอบหมาย/เจ้าของห้อง และตรวจ subStatus ก่อน
- **Acceptance test**: เรียก RPC completed โดยไม่ส่ง PIN → ต้องได้ pending_inspection ไม่ใช่ completed

## 3. ไม่มี PIN (ลูกบ้านไม่อยู่) → เข้า Inspecting ไม่ใช่ Completed

- **Current [fact]**: client ทำถูก — `noPinAvailable` → `pending_inspection` + `waiting_owner_or_admin_verification` (1111–1117) ต้องมีเหตุผล + รูป ≥1 (`validateStatusUpdate` 1096–1098)
- **Gap**: ฝั่งเซิร์ฟเวอร์ไม่มี logic นี้เลย (RPC รับ status ตรง)
- **Risk**: Critical (ต่อเนื่องข้อ 2)
- **Affected**: migration 392
- **Correction**: ย้าย fallback logic เข้า RPC
- **Acceptance test**: RPC completed + noPinAvailable → status = pending_inspection

## 4. บังคับ evidence/required fields ที่ server ไม่ใช่แค่ frontend

- **Current [fact]**: ฝั่ง client บังคับครบ (รูป 1–3, เหตุ/แนวทางแก้, วันที่ติดตาม ตามสถานะ — `validateStatusUpdate` 1082–1102)
- **Gap [High]**: ฝั่งเซิร์ฟเวอร์ไม่ validate อะไรเลย — bypass ได้หมด
- **Risk**: High
- **Affected**: migration `create_job`/`update_job_status`
- **Correction**: ทำ validation กลางใน RPC (จำนวนรูป, required fields ตามสถานะ, ขนาดไฟล์)
- **Acceptance test**: RPC completed โดยไม่มี attachment → ปฏิเสธ

## 5. หลักฐาน Routine Daily Task ต้อง trace ได้ (user/เวลา/งาน/สถานที่/ผลตรวจ/ผู้ตรวจ)

- **Current [fact]**: **ยังไม่มีฟีเจอร์ Routine Daily Task / PM** ในโค้ด — มีเพียงงานแจ้งซ่อม (job) และ timeline ต่องาน
- **Gap [High/Missing]**: ทั้งฟีเจอร์ยังไม่ถูก implement (README กล่าวถึง "งานแม่บ้าน/งานส่วนกลาง" เป็นมุมมองกรองงาน ไม่ใช่ระบบ PM ที่มี verifier)
- **Risk**: High ต่อ requirement แต่เหมาะเลื่อนออก MVP
- **Affected**: ยังไม่มีไฟล์
- **Correction**: ออกแบบตาราง `routine_tasks` + `routine_submissions` (user, timestamp server, task_id, location, verify_result, verifier_id) — เป็นงาน L (ดู roadmap)
- **Acceptance test**: บันทึก PM แล้ว query ต้องเห็นครบ 6 ฟิลด์ traceability

## 6. แยกข้อมูลลูกบ้านออกจากข้อมูลภายใน

- **Current [fact]**: client แยก view ตามบทบาท (`canViewJob` 982, resident เห็นเฉพาะห้องตัวเอง); resident มี compact tabs แยก
- **Gap [High]**: การแยกเป็นระดับ UI ไม่ใช่ระดับข้อมูล; snapshot bridge ส่ง state ทั้งก้อน; ลูกบ้านไม่ได้ถูกกันจาก internal note/committee data ในระดับ storage เมื่อ sync
- **Risk**: High (privacy)
- **Affected**: `remoteSnapshot` (1515), migration `get_app_bootstrap` (437)
- **Correction**: เลิก snapshot bridge, เสิร์ฟข้อมูลต่อบทบาทผ่าน RLS/RPC
- **Acceptance test**: บัญชี resident เรียก bootstrap → เห็นเฉพาะงานห้องตัวเอง ไม่มี admin log/committee data

## 7. ทุก state transition ต้องมี audit trail

- **Current [fact]**: มี `timeline` ต่องาน (client) + `addLog`/`audit_logs` (server table immutable)
- **Gap [Medium]**: timeline ฝั่ง client เก็บใน localStorage แก้ได้; server `job_timeline` ตารางมีแต่ **ไม่มี RPC เขียนลง** (RPC เขียนแค่ `audit_logs` และ `jobs.payload`) → timeline ไม่ถูก persist แบบ immutable ฝั่ง server
- **Risk**: Medium
- **Affected**: migration RPC ทั้งหมด (ไม่ insert `job_timeline`)
- **Correction**: ให้ทุก RPC transition insert `job_timeline` + `audit_logs`
- **Acceptance test**: หลัง assign/update ต้องมีแถวใหม่ใน `job_timeline`

## 8. Notification ล้มเหลวต้องไม่ทำ state งานเสียหาย

- **Current [fact]**: ไม่มี external notification จึงไม่มีความเสี่ยงตอนนี้; sync failure ถูกกลืน (state ยังอยู่ localStorage)
- **Gap**: เมื่อเพิ่ม LINE/Push ต้องออกแบบให้ notification เป็น side-effect แยก transaction
- **Risk**: Low ตอนนี้ / High เมื่อเพิ่ม noti
- **Correction**: ใช้ outbox pattern / queue เมื่อทำ noti

## 9. Retry ต้องไม่สร้าง task/calendar/evidence/LINE ซ้ำ (idempotency)

- **Current [fact]**: client `createJob` สร้าง id จาก `jobs.length` (1004) → ถ้า retry อาจชนกัน/ซ้ำ; webhook มี `external_id` unique แต่ job id เป็น timestamp
- **Gap [Medium]**: ไม่มี idempotency key ที่แท้จริงในเส้นทางสร้างงาน
- **Risk**: Medium
- **Affected**: `createJob` (1002), `google-forms-ingest` (43)
- **Correction**: ใช้ client-generated idempotency key + unique constraint
- **Acceptance test**: ส่งสร้างงานเดิมซ้ำ 2 ครั้ง → ได้ 1 งาน

## 10. วันที่ไทย/Asia-Bangkok ไม่เพี้ยน (off-by-one / UTC)

- **Current [fact — likely bug]**: หลายจุดใช้ `new Date().toISOString().slice(0,10)` เป็น "วันนี้" (เช่น 2823? , 4690, 5488, `todayIso` 1180) ซึ่งเป็น **UTC** ไม่ใช่ Asia/Bangkok (+07) → หลัง 17:00 น. ไทย วันที่จะเลื่อนไปวันถัดไป (off-by-one)
- **Gap**: การจัดการ timezone ไม่สม่ำเสมอ — บาง render ใช้ `toLocaleDateString('th-TH')` (ถูก) แต่ logic วันที่ใช้ ISO/UTC
- **Risk**: Medium — งานลงวันที่ผิด, due date คลาด, รายงานรายวันเพี้ยน
- **Affected**: `todayIso` (1180), `addDaysIso` (1183), `createJob` date (1040–1042), handlers 4690/5488
- **Correction**: ทำ helper `todayBangkok()` ที่คำนวณจาก timezone Asia/Bangkok เดียว ใช้ทั้งระบบ; ฝั่ง DB ใช้ `timestamptz` + แปลงตอนแสดงผล
- **Acceptance test**: ตั้งนาฬิกาเครื่องเป็น UTC 18:00 (ไทย 01:00 วันถัดไป) แล้วสร้างงาน → วันที่ต้องเป็นวันไทยที่ถูกต้อง

## สรุปช่องว่าง workflow ที่ต้องปิดก่อนใช้ข้อมูลจริง

- CRITICAL: PIN/completion enforcement ฝั่งเซิร์ฟเวอร์ (ข้อ 2, 3, 4)
- HIGH: แยกข้อมูล/เลิก snapshot bridge (ข้อ 6), server validation (ข้อ 4)
- MEDIUM: state machine (1), audit immutable ฝั่ง server (7), idempotency (9), timezone (10)
- เลื่อนออก MVP ได้: Routine Daily Task/PM (5), notification (8)
