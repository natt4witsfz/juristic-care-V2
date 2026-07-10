# Juristic Care

## Current Architecture Update

Production direction is now Supabase-first while preserving the current UX/UI and current login experience.

- Frontend config: `config.js`
- Supabase adapter: `supabase-client.js`
- Supabase migration: `supabase/migrations/202607090001_full_supabase_schema.sql`
- Edge Functions: `supabase/functions/`
- Documentation index: `docs/00-DOCUMENTATION-INDEX.md`
- Compact mode: after login/profile/PIN, users choose `Full` or `Compact`; compact is a separate quick interface and the full sidebar UI remains unchanged.
- Resident repair in compact mode opens `GOOGLE_FORM_URL` from `config.js`.

Keep `SUPABASE_ENABLED=false` for local/demo fallback. Set it to `true` only after Supabase URL, anon key, migration, buckets, RLS, and Edge Functions are ready.

Start with the documentation set:

1. `docs/00-DOCUMENTATION-INDEX.md`
2. `docs/11-SUPABASE-ARCHITECTURE.md`
3. `docs/12-SECURITY-MODEL.md`
4. `docs/14-DEPLOY-RUNBOOK.md`
5. `docs/10-QA-CHECKLIST.md`

ต้นแบบ WebApp สำหรับนิติบุคคลอาคารชุด รองรับผู้ใช้งาน 30 คน มีระบบ:

- Login ด้วยเลขห้องและรหัสผ่าน
- Dashboard ภาพรวมงานและสถานะ
- Pool งานกลางสำหรับรอรับ/มอบหมาย
- งานของฉันและงานของห้อง
- สร้างงาน มอบหมาย รับงาน และอัปเดตสถานะ
- รายชื่อทีมงานและลูกบ้าน
- Responsive สำหรับ desktop, tablet และ mobile
- ตรวจจับอุปกรณ์อัตโนมัติและสลับ UX ระหว่าง Desktop Sidebar กับ Mobile Bottom Navigation
- ระบบสองภาษา ไทย/อังกฤษ โดยภาษาเริ่มต้นคือภาษาไทย และมีปุ่มสลับภาษา `EN` / `TH`
- Flow ใหม่: Google Form Raw Pool, เจ้าหน้าที่บางรหัสคัดแยก/มอบหมาย, งานเข้า “งานของฉัน” ของผู้ได้รับมอบหมายทันที, แนบรูปและวันอัปเดตถัดไป
- Admin Log ดูได้เฉพาะ Admin และไม่มีปุ่มลบในหน้าระบบ
- Admin สามารถเข้าเมนูทีมงานเพื่อแก้ไขทีม และมอบ/ถอดสิทธิ์ Co-Admin ได้
- Co-Admin แก้ไขข้อมูลทีมงานได้ แต่ไม่สามารถมอบสิทธิ์ Co-Admin ให้ผู้อื่น
- หน้า Team รองรับแก้ชื่อ นามสกุล ชื่อเล่น ตำแหน่ง แผนก สิทธิ์มอบหมายงาน L1/L2 และรูปโปรไฟล์
- Admin/Co-Admin เพิ่มผู้ใช้งานได้ทันที
- Admin ลบผู้ใช้ได้ทันทีพร้อม export CSV งานของผู้ใช้คนนั้น
- Co-Admin กดลบแล้วระบบจะสร้างคำขอลบให้ Admin อนุมัติก่อน จึงจะลบและ export CSV ได้
- หน้า Team ต้องกดปุ่ม `บันทึก` ต่อพนักงาน 1 คนทุกครั้ง การแก้ไขจึงจะมีผลจริง
- การแก้ไขข้อมูลทีมงานโดย Admin/Co-Admin จะบันทึกรายละเอียดฟิลด์ที่เปลี่ยนทั้งหมดเข้า Admin Log
- Co-Admin แก้ไขข้อมูลทีมงานได้ แต่จะไม่เห็น ID และรหัสผ่านของพนักงาน ส่วน Admin เห็นและแก้ไขได้
- เพิ่มเมนู `ลูกบ้าน` สำหรับ Admin/Co-Admin: รองรับทะเบียนเลขห้องสูงสุด 882 ห้อง, เลขห้อง 2 รูปแบบ, เจ้าของร่วม 1 คน, ผู้เช่า/ผู้อยู่อาศัยหลายคน, ทะเบียนรถ และสถานะค่าส่วนกลางปีปัจจุบัน
- หน้า `ลูกบ้าน` เพิ่มฟิลด์ `ตึก`, ค้นหาเลขห้อง/ชื่อ/ทะเบียนรถ, กรองด้วย Dropdown ตามตึก และมีปุ่ม Export/Import CSV สำหรับอัปเดตข้อมูลหลายห้องพร้อมกัน
- รายละเอียดห้องลูกบ้านแสดงรายชื่อรวมของเจ้าของร่วม/ผู้เช่า/ผู้อยู่อาศัย โดยใช้ปุ่ม ↑/↓ จัดลำดับเอง คนที่อยู่บนสุดจะแสดงเป็นผู้อยู่อาศัยหลักในตารางหน้าลูกบ้าน
- Checkbox ในรายชื่อรวมใช้บอกว่าใครเป็นผู้อยู่อาศัย ณ ปัจจุบันเท่านั้น ไม่ได้ใช้กำหนดคนที่แสดงหน้ารวม
- ทะเบียนรถเพิ่มข้อมูลยี่ห้อ รุ่น และสีรถ พร้อมรองรับใน Export/Import CSV
- เพิ่มระบบ Work Order Assignment สำหรับสร้าง/มอบหมายงานจาก WebApp/Google Form Pool โดยรองรับวันที่งาน เวลา เลขห้อง ตึก ชั้น ผู้ติดต่อ เบอร์ รายละเอียด รูปภาพ ผู้มอบหมาย ผู้รับงาน หมายเหตุ PIN และ Timeline
- เพิ่มฟังก์ชันกลางสำหรับอนาคตย้าย Backend: `normalizeJob`, `createJob`, `assignJob`, `updateJobStatus`, `validateStatusUpdate`, `addJobTimeline`, `generateClosePin`, `checkScheduleConflict`, `canViewJob`, `canUpdateJob`, `canAssignJob`, `canSeeClosePin`, `canVerifyCompletion`, `getDashboardCounts`, `getReportCounts`
- โครงสร้าง Job ใหม่รองรับ field หลัก: `jobDate`, `startTime`, `endTime`, `roomNo`, `building`, `floor`, `contactName`, `contactPhone`, `issueDescription`, `initialAttachments`, `assignedBy`, `assignee`, `status`, `subStatus`, `note`, `closePin`, `timeline`, `statusUpdates`, `completedAt`, `noPinAvailable`, `hasScheduleConflict`
- ระบบแนบรูปในฟอร์มสร้างงานและอัปเดตสถานะใช้ปุ่ม `ถ่ายรูป` / `แนบรูป` และรูปทุกใบที่บันทึกผ่าน WebApp จะถูกประทับชื่อผู้ใช้งานพร้อม Timestamp ลงบนรูปอัตโนมัติ
- หน้า `ทีมงาน` รองรับ Export/Import CSV โดย Import ใช้หลักเพิ่มหรือแก้ไขข้อมูลเดิมตาม `id` หรือ `room_or_staff_code`; Admin เท่านั้นที่ Export/Import รหัสผ่านได้ ส่วน Co-Admin จะไม่เห็นหรือเปลี่ยนรหัสผ่านจาก CSV
- เพิ่มเมนู `งานแม่บ้าน` ต่อจาก `งานทีมช่าง` เพื่อแสดงงานที่มอบหมายให้ผู้ใช้งานแผนกแม่บ้าน
- เพิ่มเมนูต่อท้ายภาพรวม: `งานส่วนกลาง`, `งบการเงิน`, และ `ปฏิทิน` โดยปฏิทินเป็น mockup สำหรับต่อ Google Calendar API หรือฝัง Google Calendar iframe ภายหลัง
- สถานะใหม่: รับเรื่อง, รอตรวจสอบ, ตรวจสอบแล้วรอแก้ไข/อะไหล่, แก้ไขสมบูรณ์, แก้ไขแล้วรอติดตาม, แก้ไขเบื้องต้นรออะไหล่/ผู้รับเหมา, ปฏิเสธงาน และ subStatus `ช่างแจ้งเสร็จแล้ว รอตรวจสอบ`
- งานที่ช่างแจ้งเสร็จแต่ไม่มี PIN จะไม่ถูกนับเป็น Completed จนกว่า Admin/ผู้มอบหมาย/เจ้าของห้องยืนยันปิดงาน
- ระบบสร้างงานตรวจเวลาทับซ้อนของผู้ได้รับมอบหมาย ถ้าพบ overlap จะถามยืนยันก่อนสร้าง/มอบหมาย และบันทึก Timeline
- ยกเลิกระบบโต้แย้งงาน/นับถอยหลัง 30 นาทีแล้ว เมื่อมอบหมายงาน งานจะเข้า “งานของฉัน” ของผู้รับมอบหมายทันที
- สถานะ `แก้ไขแล้ว รอติดตาม` และ `แก้ไขเบื้องต้น รออะไหล่/ผู้รับเหมา` ต้องเลือกวันที่ติดตาม/อัปเดตครั้งถัดไปก่อนบันทึก
- ทุกสถานะการอัปเดต ยกเว้น `รับเรื่อง` และ `ปฏิเสธงาน` ต้องแนบรูปภาพอย่างน้อย 1 รูป และไม่เกิน 3 รูป

## ทดสอบ Work Order Flow

1. Login `ADMIN / 1234`
2. กด `สร้างงานใหม่` กรอกวันที่ เลขห้อง ผู้ติดต่อ เบอร์ รายละเอียด และเลือกผู้ได้รับมอบหมาย
3. ถ้าเลือกเวลาที่ซ้อนกับงานเดิม ระบบจะแจ้งเตือนก่อนสร้าง
4. เปิดรายละเอียดงาน จะเห็น PIN เฉพาะ Admin/ผู้มอบหมาย
5. Login เป็น Staff ที่ได้รับมอบหมาย เช่น `STAFF-02 / 1234`
6. ไปที่ `งานทีมช่าง` เปิดงาน และอัปเดตสถานะตามลำดับ
7. ถ้าปิดงานด้วย PIN ให้เลือกสถานะ Completed แล้วกรอก PIN 4 หลักให้ถูกต้อง
8. ถ้าไม่มี PIN ให้ติ๊ก `ลูกบ้านไม่อยู่ / ไม่สามารถขอ PIN ได้`, กรอกเหตุผล, แนบรูป อย่างน้อย 1 รูป งานจะเป็น `ช่างแจ้งเสร็จแล้ว รอตรวจสอบ`
9. Login กลับเป็น Admin แล้วเปิดงานนั้น กด `ยืนยันปิดงานนี้` งานจึงจะเป็น Completed จริง

## จุดที่ควรย้ายไป Backend ในอนาคต

- การ generate/ตรวจ PIN และสิทธิ์การเห็น PIN
- การตรวจเวลางานซ้อนแบบ transaction
- Timeline และ Admin/Staff Log แบบ immutable audit log
- รูปภาพแนบควรเก็บใน object storage ไม่ใช่ localStorage
- Import/Export CSV ควร validate schema ฝั่ง server

หมายเหตุ: เวอร์ชันนี้ยังเป็น mock/localStorage สำหรับออกแบบ UX/UI และทดสอบ flow เท่านั้น ยังไม่ควรใช้กับข้อมูลจริงหรือข้อมูลส่วนบุคคลจริง
- เพิ่มเมนู `Staff Log` สำหรับบันทึกกิจกรรมของทีมงานที่ไม่ใช่ Admin/Co-Admin
- `Admin Log` บันทึกกิจกรรมของ Admin และ Co-Admin พร้อม Filter วันที่ และตำแหน่ง Admin/Co-Admin

## ทดลองใช้งาน

เปิด `index.html` หรือรัน local server:

```powershell
python -m http.server 4173
```

จากนั้นเปิด `http://localhost:4173`

สำหรับทดสอบรูปแบบโดยบังคับโหมด:

- Mobile: `http://localhost:4173/?device=mobile`
- Desktop: `http://localhost:4173/?device=desktop`

บัญชีตัวอย่าง:

- ผู้ดูแล: `ADMIN` / `1234`
- เจ้าหน้าที่มอบหมายงาน: `STAFF-01` / `1234`
- ทีมช่าง: `STAFF-02` / `1234`
- ลูกบ้าน: `A-0201` / `1234`

ข้อมูลในต้นแบบเก็บใน `localStorage` ของ browser

## ภาษา

- ภาษาเริ่มต้น: ไทย
- กดปุ่ม `EN` เพื่อเปลี่ยนเป็นภาษาอังกฤษ
- กดปุ่ม `TH` เพื่อกลับเป็นภาษาไทย
- ระบบจำภาษาที่เลือกไว้ใน `localStorage`
