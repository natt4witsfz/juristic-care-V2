# 11 — Open Questions & Access-Control Matrix

## E. Access-Control Matrix (สร้างจากโค้ดจริง — client `app.js`)

สถานะ: ✔ อนุญาต · ✖ ไม่อนุญาต · △ ขึ้นกับ permission/flag · ? ยังไม่ชัด/ต้องยืนยัน

| ความสามารถ | Admin | Co-Admin | Staff (มอบหมาย) | ช่าง/แม่บ้าน | กรรมการ | ลูกบ้าน | ผู้แจ้งภายนอก |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ดูงาน (ที่เกี่ยวข้อง) | ✔ | ✔ | ✔ | ✔(ที่รับ) | △ | ✔(ห้องตน) | ✖ |
| สร้างงาน | △createJob | △ | △ | △ | ✖ | △ | ผ่านฟอร์ม |
| มอบหมายงาน | ✔ | ✔ | △assignL1/L2 | ✖ | ✖ | ✖ | ✖ |
| แก้ไข/อัปเดตสถานะ | ✔ | ✔ | ✔(assignedBy) | ✔(assignee) | ✖ | ✖ | ✖ |
| ปิดงาน (completed) | ✔ | ✔ | ✔ | ✔+PIN | ✖ | ✖ | ✖ |
| อนุมัติปิดงาน (verify) | ✔ | ✔ | ✔(assignedBy) | ✖ | ✖ | ✔(ห้องตน) | ✖ |
| เห็น PIN ปิดงาน | ✔ | ✔ | ✔(assignedBy/reporter) | ✖ | ✖ | ✔(ห้องตน) | ✖ |
| ดู PII ลูกบ้าน | ✔ | ✔(ไม่เห็นรหัสผ่าน) | △manageResidents | ✖? | ? | ✖(ห้องอื่น) | ✖ |
| ดูข้อมูลกรรมการ | ✔ | ✔ | ? | ✖ | ✔ | ✖ | ✖ |
| ดู routine ภายใน | ✔ | ✔ | ✔ | ✔ | ? | ✖ | ✖ |
| อัปโหลดหลักฐาน | ✔ | ✔ | ✔ | ✔ | ✖ | △ | ✖ |
| ลบหลักฐาน | ✔? | ? | ✖ | ✖ | ✖ | ✖ | ✖ |
| ตั้งค่า/แก้ผู้ใช้ | ✔ | ✔(ไม่เห็นรหัส/ไม่มอบ Co-Admin) | ✖ | ✖ | ✖ | ✖ | ✖ |
| Export ข้อมูล | ✔(รวมรหัสผ่าน) | △(ไม่รวมรหัส) | △importExport | ✖ | ✖ | ✖ | ✖ |
| ดู audit log | ✔(admin log) | ✔ | ✔(staff log) | ✔(staff log) | ✖ | ✖(ของตน) | ✖ |
| ตั้งค่าระบบ/สิทธิ์ | ✔ | △managePermissions | ✖ | ✖ | ✖ | ✖ | ✖ |

**หมายเหตุสำคัญ**: matrix นี้สะท้อน **ความตั้งใจฝั่ง client** เท่านั้น ในทางปฏิบัติ (localStorage) ทุกช่องถูกข้ามได้เพราะไม่มี server enforcement (F-03) เมื่อเปิด Supabase RLS/RPC จะบังคับบางส่วน แต่ snapshot bridge (F-05) ยังลบล้างอยู่

### จุดที่ matrix ชี้ให้เห็นปัญหา
- **ช่างปิดงานได้เอง** (client ต้อง PIN, server ไม่ต้อง) → F-04
- **Co-Admin = admin ใน `is_admin_account()`** ฝั่ง DB (migration:241) แต่ client แยกสิทธิ์ (เช่นไม่เห็นรหัสผ่าน) → ไม่สอดคล้อง ต้องยืนยันเจตนา
- **กรรมการ/ช่าง เข้าถึง PII/committee data** — ยังไม่มีขอบเขตชัดใน DB (ตาราง PII ไม่มี policy) → F-10

## Open Questions (ต้องการคำตอบจากผู้ว่าจ้าง)

### สิทธิ์และบทบาท
1. Co-Admin ควรมีสิทธิ์เท่า Admin หรือน้อยกว่า? (DB ปฏิบัติเท่ากัน, client ต่างกัน — ต้องเลือกทางเดียว)
2. กรรมการ (committee) ควรเห็นข้อมูลอะไรบ้าง? เห็น PII ลูกบ้านห้องอื่นได้ไหม?
3. ช่าง/แม่บ้าน ควรเห็นชื่อ/เบอร์ลูกบ้านของงานที่ตัวเองรับเท่านั้น ใช่ไหม?
4. "ผู้แจ้งภายนอก/ผู้รับเหมาที่ห้าม login" — ต้องรองรับ flow ให้ผู้รับเหมาอัปเดตงานโดยไม่ login อย่างไร (ลิงก์ token ชั่วคราว?)

### Workflow
5. ใครบ้างมีสิทธิ์ "อนุมัติปิดงาน" กรณีไม่มี PIN — admin/ผู้มอบหมาย/เจ้าของห้อง พอไหม หรือกรรมการด้วย?
6. Routine Daily Task/PM: ต้องการในเฟสไหน? ใครเป็น verifier? ต้องมี GPS/location จริงหรือแค่ระบุพื้นที่?
7. PIN ปิดงาน 4 หลัก: สุ่มต่องาน หรือใช้ PIN ลูกบ้าน? อายุ PIN?

### ข้อมูล & Integration
8. Google Form/Sheet/Drive/Apps Script ปัจจุบัน (ตาม DEPLOYED-URLS.md) — ยังใช้อยู่หรือจะเลิก? การตั้งค่า deployment ของ Apps Script เป็น "anyone" หรือไม่?
9. ต้องการ LINE OA / Web Push ในเฟสไหน?
10. ข้อมูลจริงที่จะย้ายเข้าระบบมาจากไหน (Excel/Sheet เดิม)? ปริมาณห้อง/ผู้ใช้จริง?

### Deployment & Compliance
11. Hosting production ต้องการ custom domain หรือคง GitHub Pages?
12. มีที่ปรึกษา/นโยบาย PDPA แล้วหรือยัง? ต้องการ retention/consent flow แบบใด?
13. ระบบนี้จะใช้กี่โครงการ (single vs multi-tenant)?
14. งบ/ข้อจำกัดค่าใช้จ่าย Supabase/hosting?

### Repository
15. ขอสิทธิ์เข้าถึง GitHub repo จริง (`natt4witsfz/juristic-care-pilot`) เพื่อสแกน git history หา secret ที่อาจเคย commit — โฟลเดอร์ที่ตรวจไม่ใช่ git working copy

## ข้อมูลที่ยังขาดสำหรับการตรวจให้สมบูรณ์
- git history / branches / commit ที่ผ่านมา
- Supabase instance ทดสอบ (เพื่อยืนยัน RLS/RPC/Storage จริง)
- การตั้งค่า Apps Script / Google OAuth scopes จริง
- ปริมาณและรูปแบบข้อมูลจริงที่จะนำเข้า
