# 00 — บทสรุปผู้บริหาร (Executive Summary)

เอกสารนี้เป็นผลการตรวจสอบทางเทคนิค (technical audit) ของโปรเจกต์ **Juristic Care** ระบบบริหารงานนิติบุคคลอาคารชุด ทำแบบอ่านอย่างเดียว (read-only) ยังไม่มีการแก้ไข source code ตามข้อกำหนด รายงานอ้างอิงหลักฐานจากไฟล์และเลขบรรทัดจริงในวันที่ตรวจสอบ (2026-07-10)

> คำเตือนสำคัญ: ระบบนี้ยัง **ไม่ปลอดภัยสำหรับข้อมูลลูกบ้านจริง** และ **ยังไม่พร้อม deploy production** ตอนนี้ยังเหมาะกับ local development และการออกแบบ/ทดสอบ flow เท่านั้น (README บรรทัด 86 ยืนยันเจตนานี้ไว้แล้ว)

## สถานะโปรเจกต์โดยรวม

โปรเจกต์อยู่ในสถานะ **ต้นแบบ (prototype) ที่ทำงานได้จริงในฝั่ง front-end** แต่ backend ยังไม่ได้เชื่อมต่อจริง สถาปัตยกรรมปัจจุบันเป็น static web app (vanilla JavaScript ไฟล์เดียวขนาดใหญ่ `app.js` 5,669 บรรทัด) ที่เก็บข้อมูลทั้งหมดใน `localStorage` ของ browser มีการเขียนโครง Supabase (schema, RLS, Edge Functions) เตรียมไว้แล้ว แต่ยัง **ปิดใช้งาน** (`config.js` บรรทัด 4: `SUPABASE_ENABLED: false`) และ logic ธุรกิจสำคัญ (โดยเฉพาะการตรวจ PIN ปิดงาน) ยัง **ไม่ถูกบังคับที่ฝั่งเซิร์ฟเวอร์**

สถาปัตยกรรมที่เหมาะสมสำหรับโปรเจกต์ระยะนี้คือ **modular monolith แบบ Supabase-first** ซึ่งทีมเลือกไว้ถูกต้องแล้ว ไม่จำเป็นต้องทำ microservices

## สิ่งที่ทำงานได้จริง (verified)

- หน้าเว็บโหลดและ serve ได้ปกติ: `index.html` (HTTP 200), `app.js` (HTTP 200) — ทดสอบด้วย `python3 -m http.server`
- `node --check` ผ่านทุกไฟล์ JS (`app.js`, `profiles.js`, `supabase-client.js`, `config.js`) ไม่มี syntax error
- Flow งานฝั่ง client ครบวงจร: สร้างงาน → มอบหมาย → อัปเดตสถานะ → ปิดงานด้วย PIN → fallback ไม่มี PIN → ยืนยันปิดงาน (`app.js` บรรทัด 1002–1163)
- ระบบสองภาษา ไทย/อังกฤษ ค่าเริ่มต้นเป็นไทย ทำงานได้ (`app.js` I18N)
- ตรรกะตรวจเวลางานซ้อน (`checkScheduleConflict`, บรรทัด 964)
- Profile gate + PIN ต่อโปรไฟล์สำหรับลูกบ้าน (Netflix-style) พร้อม hash SHA-256 (`profiles.js`)
- โครง Supabase schema, RLS policies, Storage buckets แบบ private, และ Edge Functions 3 ตัว เขียนไว้ครบและมีคุณภาพดีในหลายจุด

## สิ่งที่ยังไม่ทำงาน / ยังไม่เชื่อมจริง

- **Supabase ยังปิดอยู่** — ข้อมูลทั้งหมดอยู่ใน localStorage ยังไม่มี backend จริง
- **การบังคับ PIN ปิดงานฝั่งเซิร์ฟเวอร์ไม่มี** — RPC `update_job_status` (migration บรรทัด 392) ไม่ตรวจ PIN เลย ทำให้ผู้รับงานตั้งสถานะเป็น `completed` ได้เองผ่าน RPC โดยข้าม PIN
- **การแยกข้อมูลลูกบ้านออกจากข้อมูลภายในยังไม่สมบูรณ์** — RPC `get_app_bootstrap` (บรรทัด 437) คืน "snapshot ทั้งก้อน" ให้บัญชี staff ทุกคน และ `save_client_snapshot` (บรรทัด 424) ให้ staff เขียนทับ state ทั้งระบบได้ ซึ่งลบล้างการควบคุมสิทธิ์ระดับแถว (RLS) ที่ออกแบบไว้
- ปฏิทิน (Google Calendar) เป็น mockup ยังไม่ต่อ API จริง (README บรรทัด 58)
- LINE OA / Web Push / งาน PM routine daily task ยังไม่มีในโค้ด
- ไม่มีระบบ audit trail ที่แก้ไม่ได้จริง (client เก็บใน localStorage แก้ได้ทั้งหมด)

## สิ่งที่ยังไม่ได้ตรวจสอบ (missing information / not verified)

- **ไม่สามารถตรวจ git history ได้** — โฟลเดอร์ที่ mount (OneDrive) ไม่ใช่ git working copy (`git status` คืน "not a git repository") จึงตรวจ commit, branch, ignored files ไม่ได้ ต้องขอ access repo GitHub จริง (`DEPLOYED-URLS.md` อ้างถึง `github.com/natt4witsfz/juristic-care-pilot`)
- ยังไม่ได้ทดสอบ Supabase ของจริง (RLS, RPC, Storage) เพราะไม่มี instance และห้ามแตะ production
- ยังไม่ได้ทดสอบ Edge Functions runtime (ไม่มี Deno ในสภาพแวดล้อมตรวจสอบ)
- ยังไม่ได้ตรวจ Google Apps Script / Google Sheet ตัวจริง (อยู่นอก repo, ห้ามแตะ)

## 5 ความเสี่ยงสูงสุด (Top 5 Risks)

1. **[CRITICAL] Stored XSS จากงานที่แจ้งผ่าน Google Form/WebApp** — ฟิลด์งาน (`title`, `roomNo`, `contactName`, `contactPhone`, `note`) ถูก render เข้า `innerHTML` โดยไม่ผ่าน `esc()` (`app.js` บรรทัด 3276, 4417–4427) และ Edge Function `google-forms-ingest` เก็บ payload ดิบลงงาน ผู้แจ้งภายนอกจึงฝัง `<script>` ให้รันในหน้าเจ้าหน้าที่/แอดมินได้
2. **[CRITICAL] บังคับ PIN ปิดงานที่ฝั่ง client เท่านั้น** — RPC `update_job_status` ไม่ตรวจ PIN ทำให้กฎธุรกิจหลัก ("ปิดงานต้องมี PIN หรือเข้าสถานะรอตรวจสอบ") ถูกข้ามได้เมื่อเปิด Supabase
3. **[CRITICAL] รหัสผ่านเก็บเป็น plaintext และ default ทุกบัญชีเป็น `1234`** — (`app.js` บรรทัด 628–640, 5453) และ CSV export รหัสผ่านแบบ plaintext (บรรทัด 1764) เสี่ยงข้อมูลรั่วร้ายแรงเมื่อใช้จริง
4. **[HIGH] Snapshot bridge ลบล้าง RLS** — `get_app_bootstrap`/`save_client_snapshot` ส่งและรับ state ทั้งก้อนต่อบัญชี staff ทำให้ PII ลูกบ้านทั้งอาคารไหลไปยัง staff ทุกคน และ staff คนใดก็เขียนทับข้อมูลทั้งระบบได้
5. **[HIGH] ไม่มี server-side authorization/validation จริงในเส้นทางที่ใช้งานอยู่** — สิทธิ์ทั้งหมดตัดสินใน client (localStorage) แก้ไขค่าใน DevTools ก็ยกระดับสิทธิ์เป็น admin ได้ทันที

## ความปลอดภัยในการใช้งานแต่ละระดับ

| ระดับการใช้งาน | ปลอดภัยหรือไม่ | เหตุผลสั้น ๆ |
| --- | --- | --- |
| Local development | ใช่ | รันได้ ทดสอบ flow ได้ ไม่มีข้อมูลจริง |
| Internal pilot (ข้อมูลปลอม) | ได้แบบมีเงื่อนไข | ใช้เพื่อ demo/UX ได้ แต่ห้ามใส่ข้อมูลบุคคลจริง |
| ข้อมูลลูกบ้านจริง (PII) | **ไม่** | ยังไม่มี server auth จริง, รหัสผ่าน plaintext, XSS, PIN client-only |
| Production deployment | **ไม่** | ต้องปิด 3 ช่อง CRITICAL และเปิด Supabase-first ให้ครบก่อน |

## การกระทำถัดไปทันที (Immediate Next Action)

รอการอนุมัติจากผู้ว่าจ้างเลือก 1 ใน 5 ตัวเลือก (A–E ท้ายรายงาน) แนะนำเริ่มที่ **Batch 1 (option D)**: แก้ XSS ด้วยการ `esc()` ทุกฟิลด์งานที่เข้า DOM, เปลี่ยน default password ให้เป็นแบบสุ่มต่อบัญชี, และเพิ่มการตรวจ PIN ในเส้นทางปิดงานฝั่งเซิร์ฟเวอร์ — เป็นชุดเล็ก ตรวจทานง่าย ความเสี่ยง regression ต่ำ

รายละเอียดทั้งหมดดูเอกสาร 01–11 และตาราง Master Findings ใน `10-remediation-roadmap.md`
