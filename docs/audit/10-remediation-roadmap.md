# 10 — Master Findings & Remediation Roadmap

## Master Findings Table

Severity: Critical / High / Medium / Low / Info · Effort: S(<0.5วัน) / M(0.5–2วัน) / L(3–5วัน) / XL(>1สัปดาห์) · Regression risk / Blocking deploy

| ID | Sev | Category | Finding | Evidence (file:line) | User impact | Security/Ops impact | Recommended fix | Effort | Regr. risk | Required test | Block deploy |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| F-01 | Critical | Security/XSS | ฟิลด์งาน render เข้า innerHTML ไม่ escape | app.js:3276,4413-4427; profiles.js:89,151 | รันสคริปต์ในเซสชันแอดมิน | เข้าครองระบบ, ขโมย PII | ใช้ esc() ทุก field ผู้ใช้ | M | ต่ำ | AT-11 | **Yes** |
| F-02 | Critical | Auth | รหัสผ่าน plaintext + default `1234` ทุกบัญชี | app.js:628-640,5453,1764; admin-users:51 | บัญชีถูกเดา/รั่ว | ยึดบัญชีทั้งระบบ | สุ่มรหัส/บังคับเปลี่ยน/ไม่ export | M | กลาง | AT-3,unit | **Yes** |
| F-03 | Critical | Authorization | สิทธิ์ตัดสินฝั่ง client ล้วน | app.js:826-851 | — | ยกระดับสิทธิ์ผ่าน DevTools | บังคับ RLS/RPC จริง | L | กลาง | AT-8,RLS | **Yes** |
| F-04 | Critical | Workflow | PIN/completion ไม่บังคับฝั่งเซิร์ฟเวอร์ | migration:392-422 | ปิดงานเถื่อน | กฎธุรกิจถูกข้าม | เพิ่ม PIN/transition check ใน RPC | M | กลาง | AT-4,AT-5,AT-7 | **Yes** |
| F-05 | High | Data/Privacy | Snapshot bridge ลบล้าง RLS + รั่ว PII | migration:424-458; app.js:1515 | — | staff เห็น/แก้ข้อมูลทั้งอาคาร | เลิก bridge, RPC ต่อ entity | L | สูง | AT-6,RLS | **Yes** |
| F-06 | High | Security/CORS | Edge Functions CORS `*` | admin-users:4,gf-ingest:5,file:4 | — | CSRF/abuse ข้ามโดเมน | จำกัด origin | S | ต่ำ | integration | **Yes** |
| F-07 | High | Security | webhook ข้ามการตรวจถ้า secret ว่าง | google-forms-ingest:20-22 | งานปลอมถูกยัด | สร้าง job/XSS | บังคับ secret เสมอ + HMAC | S | ต่ำ | AT-10 | **Yes** |
| F-08 | High | Reliability | ข้อมูลจริงอยู่ localStorage เดียว ไม่มี backup | app.js:1276-1285 | ข้อมูลหายถาวร | data loss | ย้าย Supabase + backup | L | กลาง | E2E | **Yes** |
| F-09 | High | Workflow | ไม่มี server validation required fields/รูป | migration:330-408 | — | หลักฐานไม่ครบ | validate ใน RPC | M | กลาง | AT-7 | Yes |
| F-10 | Medium | DB | ตาราง PII ไม่มี policy/RPC อ่าน | migration:460-475 | เข้าถึงข้อมูลไม่ได้/ผ่าน bridge | inconsistent access | เพิ่ม policy/RPC | M | กลาง | RLS | Yes |
| F-11 | Medium | Workflow | ไม่มี state machine บังคับ transition | app.js:1104; migration:392 | สถานะผิดเพี้ยน | ข้อมูลไม่ถูกต้อง | ตาราง allowed transitions | M | กลาง | AT-* | No |
| F-12 | Medium | i18n/Time | ใช้ UTC เป็น "วันนี้" → off-by-one | app.js:1180,1183,1040,4690,5488 | วันที่งานผิด | รายงานคลาด | helper Asia/Bangkok | M | กลาง | AT-9 | Yes |
| F-13 | Medium | Reliability | ไม่มี idempotency สร้างงาน/webhook | app.js:1004; gf-ingest:43 | งานซ้ำ | ข้อมูลซ้ำ | idempotency key+unique | M | กลาง | AT-10 | No |
| F-14 | Medium | Audit | RPC ไม่เขียน job_timeline (immutable) | migration RPC ทั้งหมด | — | trail ไม่ครบ/แก้ได้ | insert job_timeline ทุก transition | S | ต่ำ | AT-12 | Yes |
| F-15 | Medium | Security | ไม่มี rate limit/brute-force protection | app.js login; profiles.js:167 | — | เดา PIN/รหัส | throttle/lockout | M | ต่ำ | — | Yes |
| F-16 | Medium | Security | ไม่มี CSP/security headers | index.html (ไม่มี) | — | คลิกแจ็ค/inject | เพิ่ม CSP ที่ hosting | S | ต่ำ | — | Yes |
| F-17 | Medium | Repo | ไม่ใช่ git working copy + ไม่มี .gitignore | git status (fatal) | — | เสี่ยง commit secret | ตั้ง git + .gitignore + secret scan | S | ต่ำ | — | Yes |
| F-18 | Low | Perf | รูปเป็น dataURL ใน localStorage เต็มเร็ว | app.js:5385-5431 | แอปค้าง/เต็ม | — | ใช้ Storage จริง | M | ต่ำ | — | No |
| F-19 | Low | Evidence | watermark timestamp จาก client แก้ได้ | app.js:5374,5415 | — | หลักฐานอ่อน | เวลา server-side | M | ต่ำ | — | No |
| F-20 | Low | Supply chain | CDN ไม่มี SRI | index.html:567,13 | — | CDN ถูกแก้ | เพิ่ม SRI/self-host | S | ต่ำ | — | No |
| F-21 | Low | Quality | God-file app.js 5,669 บรรทัด | app.js | — | maintainability | แยก module ค่อยเป็นค่อยไป | XL | สูง | regression | No |
| F-22 | Info | Docs | legacy supabase-schema.sql ซ้ำ migration | supabase-schema.sql:1-4 | — | สับสน | ย้าย docs/legacy | S | ต่ำ | — | No |
| F-23 | Medium | Data expose | DEPLOYED-URLS.md เปิด endpoint pilot จริง | DEPLOYED-URLS.md:5-17 | — | attack surface | ตรวจสิทธิ์ Apps Script/จำกัด | S | ต่ำ | — | No |

## Top 10 Findings เรียงตามความเสี่ยง
1. F-01 XSS จากงาน (Critical)
2. F-04 PIN/completion ไม่บังคับ server (Critical)
3. F-02 รหัสผ่าน plaintext/`1234` (Critical)
4. F-03 authorization client-only (Critical)
5. F-05 snapshot bridge รั่ว PII (High)
6. F-08 ข้อมูลใน localStorage ไม่มี backup (High)
7. F-07 webhook ข้ามตรวจ secret (High)
8. F-06 CORS `*` (High)
9. F-09 ไม่มี server validation (High)
10. F-12 timezone off-by-one (Medium แต่กระทบข้อมูลทุกงาน)

## Quick Wins (<1 วัน)
- F-06 จำกัด CORS origin (S)
- F-07 บังคับ webhook secret เสมอ (S)
- F-16 เพิ่ม CSP/security headers (S)
- F-17 ตั้ง .gitignore + secret scan (S)
- F-14 insert job_timeline ใน RPC (S)
- F-20 เพิ่ม SRI (S)
- F-01 escape fields (M แต่ทำได้เร็ว, กระทบสูง — จัดเป็น Batch 1)

## สิ่งที่ยังไม่ควรแก้ตอนนี้ (Do NOT change yet)
- F-21 แยก God-file — ความเสี่ยง regression สูง ทำหลังปิด security และมี test แล้ว
- Apps Script sync path — อย่าลบจนยืนยันว่าไม่ใช้ (ทำ deprecation note ก่อน)
- UX/UI layout — ห้ามแตะตาม WORK-LOCK-NO-UX-UI.md เว้นผู้ว่าจ้างสั่ง
- legacy supabase-schema.sql — เก็บอ้างอิงไว้ก่อน (แค่ย้ายโฟลเดอร์)

## โค้ดที่ over-engineered / ไม่จำเป็น
- สอง sync path (Apps Script + Supabase) พร้อมกัน — ควรเหลือทางเดียว
- snapshot bridge — ทั้งชุดเป็น anti-pattern ควรแทนด้วย RPC ต่อ entity
- normalizeJob เดา default มากเกิน — ควร validate ที่ boundary แทน

## เอกสาร/เทสต์ที่ขาด
- ขาด: unit/integration/e2e ทั้งหมด (ดู `08`), ADR (architecture decision records), PDPA policy, runbook incident/backup-restore, API contract ของ RPC
- ขาด: CI/CD, .gitignore, package.json, lint config

## MVP Scope ที่แนะนำ
**เข้า MVP**: login+auth จริง (Supabase), งานแจ้งซ่อม lifecycle เต็ม + PIN/verify ฝั่ง server, แยกข้อมูลลูกบ้านจริง, upload หลักฐานเข้า Storage, audit trail server, ทะเบียนลูกบ้าน/ทีมงาน, dashboard, สองภาษา
**เลื่อนออก (defer)**: Routine Daily Task/PM system, Google Calendar API จริง, LINE OA, Web Push, งบการเงินจริง, Organization chart ขั้นสูง, multi-tenant หลายโครงการ

## Roadmap

### 30 วัน (ปิด Critical + เปิด Supabase-first อย่างปลอดภัย)
- Batch 1 (ดูล่าง): F-01, F-02, F-04 (client+server), F-06, F-07
- F-03/F-05: บังคับ authz ที่ RLS/RPC, เลิก snapshot bridge (เริ่มจาก jobs + PII)
- F-17/F-16: git hygiene + CSP
- ตั้ง Supabase staging + รัน migration + RLS tests (AT-4,5,7,8,12)

### 60 วัน (ความถูกต้อง + reliability)
- F-08 ย้าย source of truth → Supabase + backup + ทดสอบ restore
- F-09 server validation, F-12 timezone, F-13 idempotency, F-14 timeline, F-11 state machine, F-15 rate limit
- F-18 upload เข้า Storage จริง + progress/retry
- ตั้ง CI (lint/check/unit/smoke) + unit tests ชั้น 2

### 90 วัน (พร้อม production จำกัด + เตรียมฟีเจอร์เลื่อน)
- PDPA policy + redaction + retention
- E2E suite เต็ม, monitoring/alerting, runbook
- เริ่มออกแบบ Routine Daily Task/PM (ฟีเจอร์ใหม่)
- พิจารณา custom domain + Cloudflare/Vercel
- แยก God-file (F-21) ทีละ module พร้อม test คุ้มกัน

## Batch 1 — ชุดแรกที่เสนอ (เล็ก ตรวจทานง่าย)
ขอบเขตจำกัดเพื่อความเสี่ยงต่ำ:
1. **F-01**: เพิ่ม `esc()` รอบทุก field ผู้ใช้ใน `jobRow` (3276), `openJob` detail-grid + title (4403,4417-4427), `attachmentHtml`, และ `p.name`/`profile.name` ใน `profiles.js` (89,151). ไม่แตะ layout/CSS
2. **F-02 (client)**: เปลี่ยน default password ผู้ใช้ใหม่จาก `"1234"` เป็นค่าสุ่ม + toast แจ้งรหัสชั่วคราวให้ตั้งใหม่ (ไม่แตะ seed demo accounts ที่ระบุใน README/QA เพื่อคง flow ทดสอบ — ทำ flag แยก demo)
3. **F-06/F-07**: จำกัด CORS origin + บังคับ `x-ingest-secret` เสมอ ใน 3 Edge Functions
4. เพิ่ม test: unit ของ escaping + AT-11 (XSS) + AT-10 (webhook)

Batch 1 ไม่แตะ: DB migration structure ใหญ่, God-file refactor, UX/UI, snapshot bridge (แยกเป็น Batch 2 เพราะเสี่ยงกว่า)
