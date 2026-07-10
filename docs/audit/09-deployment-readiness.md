# 09 — Deployment Readiness & Future Architecture

ประเมินความพร้อม deploy โดย **ไม่ deploy จริง**

## 1. ความเหมาะสมของ stack ต่อระดับการใช้งาน

| ระดับ | พร้อมหรือไม่ | เงื่อนไข |
| --- | --- | --- |
| Pilot (ข้อมูล demo) | ✔ ได้ | static hosting + localStorage เพียงพอ; ห้ามใส่ PII จริง |
| Internal production จำกัด | ✖ ยัง | ต้องเปิด Supabase-first + ปิดช่อง Critical ก่อน |
| Full condominium production | ✖ ยัง | ต้องครบ auth/authz จริง, backup, monitoring, PDPA |
| หลายโครงการ (multi-tenant) | ✖ ยัง | schema ปัจจุบันเป็น single-tenant; ต้องเพิ่ม `project_id`/tenant isolation |

## 2. สถาปัตยกรรม deploy ที่แนะนำ (อิงโค้ดจริง)

โค้ดออกแบบมาเพื่อ **Supabase-first + static frontend** อยู่แล้ว จึงแนะนำต่อยอดตามนี้ ไม่เปลี่ยนแนวใหญ่:

- **Frontend**: static hosting — คงใช้ **GitHub Pages** (มีอยู่แล้ว `natt4witsfz.github.io/juristic-care-pilot`) สำหรับ pilot; ย้ายไป **Cloudflare Pages** หรือ **Vercel** เมื่อต้องการ custom domain + security headers + preview per-branch
- **Backend/DB/Auth/Storage**: **Supabase** (schema/RLS/Edge Functions พร้อมแล้ว)
- **Integration**: Google Form → Supabase Edge Function (มีแล้ว); Calendar/LINE เพิ่มภายหลัง

**ไม่แนะนำ**: Google Apps Script เป็น backend หลัก (เส้นทางเก่า) เพราะขาด RLS จริง, quota/execution limits, และตรวจสิทธิ์ยาก — ให้ลดบทบาทเป็นตัวรับฟอร์ม/บริดจ์เท่านั้น หรือเลิก

**ไม่แนะนำ microservices / Firebase เปลี่ยนใหม่** — ไม่มีเหตุผลเชิงปฏิบัติการรองรับ และจะเสียงานที่ลงทุนกับ Supabase ไปแล้ว

## 3. เหตุผลการเลือก (ไม่เลือกเพราะความนิยม)
- Supabase: Postgres + RLS ให้ authorization ระดับแถวที่ระบบนี้ต้องการ (แยกข้อมูลลูกบ้าน/บทบาท), มี Auth + private Storage + Edge Functions ครบ, ทีมเขียน schema ไว้แล้ว
- Static frontend: แอปเป็น SPA ไม่มี SSR ความต้องการ hosting ต่ำ ต้นทุนถูก

## 4. Deployment Checklist

### Development
- [ ] เพิ่ม `.gitignore` (config จริง, media, node_modules)
- [ ] `package.json` + scripts (serve/check/lint/test)
- [ ] Supabase project แยกสำหรับ dev

### Staging
- [ ] Supabase project staging + รัน migration
- [ ] seed ข้อมูล **ปลอม** เท่านั้น
- [ ] เปิด `SUPABASE_ENABLED=true` ทดสอบ E2E/RLS

### Production
- [ ] Supabase project prod แยกจาก staging
- [ ] Secrets ผ่าน Supabase Function secrets / hosting env (ห้ามใส่ service_role ใน frontend — กฎ WORK-LOCK บรรทัด 51)
- [ ] รัน migration + ตรวจ RLS ครบทุกตาราง (รวมตาราง PII)
- [ ] Storage buckets private + policy ตรวจแล้ว
- [ ] Custom domain + HTTPS (auto ผ่าน Cloudflare/Vercel)
- [ ] CORS จำกัด origin (Edge Functions + Supabase Auth allowed URLs)
- [ ] Security headers + CSP
- [ ] CI/CD (GitHub Actions): lint → check → test → deploy
- [ ] Smoke test หลัง deploy (login + workflow หลัก)
- [ ] Monitoring: Supabase logs + uptime + error reporting
- [ ] Backups: เปิด Supabase daily backup + **ทดสอบ restore จริง**
- [ ] Rollback: เก็บ migration ย้อนกลับได้ + tag release
- [ ] Data migration: จาก localStorage/Apps Script → Supabase (script + ตรวจสอบ)
- [ ] Incident response runbook
- [ ] Cost monitoring (Supabase usage/quota)
- [ ] Access revocation + employee turnover: ปิดบัญชี, rotate service_role, ถอนสิทธิ์ทันทีเมื่อพนักงานออก

## 5. เงื่อนไขขั้นต่ำก่อนใส่ข้อมูลลูกบ้านจริง (Minimum conditions)

ต้องครบ **ทุกข้อ**:
1. ✅ ปิด XSS (SEC-01, SEC-05) — escape ทุก field
2. ✅ เอา default password `1234` + plaintext ออก, บังคับเปลี่ยนครั้งแรก
3. ✅ เปิด Supabase-first และ authorization บังคับที่ RLS/RPC จริง (เลิกพึ่ง client)
4. ✅ เลิก snapshot bridge → เสิร์ฟข้อมูลต่อบทบาท (แยกข้อมูลลูกบ้าน)
5. ✅ บังคับ PIN/required fields/transition ที่ RPC ฝั่งเซิร์ฟเวอร์
6. ✅ CORS จำกัด + webhook secret บังคับเสมอ
7. ✅ Backup เปิด + ทดสอบ restore สำเร็จ
8. ✅ นโยบาย PDPA เบื้องต้น (retention/consent/สิทธิ์ลบ) + redact PII ใน log
9. ✅ แก้ timezone Asia/Bangkok ให้สม่ำเสมอ

จนกว่าจะครบ ให้ใช้ข้อมูล demo เท่านั้น
