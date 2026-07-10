# 02 — Build & Test Baseline (ผลการรัน จริง)

ทำแบบไม่แก้ source code ตามข้อกำหนด รายงานคำสั่งจริง ผลลัพธ์ และการวินิจฉัยสาเหตุ

## บริบทสภาพแวดล้อม

- โฟลเดอร์ที่ mount ไม่ใช่ git working copy: `git status` → `fatal: not a git repository` **[ข้อมูลที่ยังขาด]** ตรวจ git history/branch/ignored ไม่ได้จากที่นี่
- ไม่มี `package.json`, ไม่มี lockfile, ไม่มี `.gitignore`, ไม่มี test framework, ไม่มี CI/CD config, ไม่มี Dockerfile
- Stack: static HTML/CSS/vanilla JS + Supabase (SQL + Deno Edge Functions) — **ไม่มี build system**

## ตารางผลการรัน

| ขั้นตอน | คำสั่งที่ใช้ | ผล | หมายเหตุ / สาเหตุ |
| --- | --- | --- | --- |
| ติดตั้ง dependency | ไม่มี (ไม่มี package manager) | N/A | ไม่มี dependency ฝั่ง build; runtime โหลด Supabase จาก CDN |
| Lint | ไม่มี config lint ในโปรเจกต์ | N/A | ควรเพิ่ม ESLint (ดู `08`) |
| Type checking | ไม่มี (เป็น vanilla JS ไม่มี TS config) | N/A | Edge Functions เป็น `.ts` แต่ไม่มี tsconfig/deno.json |
| Syntax check | `node --check app.js` (และ profiles/supabase-client/config) | ✅ ผ่านทุกไฟล์ | ไม่มี syntax error |
| Unit tests | — | ❌ ไม่มี test | ไม่มีไฟล์ test ใด ๆ ในโปรเจกต์ |
| Integration tests | — | ❌ ไม่มี | — |
| E2E tests | — | ❌ ไม่มี | — |
| Production build | — | N/A | static ไม่ต้อง build |
| Local dev startup | `python3 -m http.server 4173` | ✅ ทำงาน | `index.html` HTTP 200 (44,203 bytes), `app.js` HTTP 200 (329,618 bytes) |
| Database validation | — | ⚠️ ทำไม่ได้ | ไม่มี Supabase instance และห้ามแตะ production; ตรวจได้แค่ syntax SQL เชิงอ่าน |
| Migration status | — | ⚠️ ทำไม่ได้ | ไม่มี Supabase CLI / instance ที่อนุญาตให้ทดสอบ |

## รายละเอียดผลที่ตรวจแล้ว

### node --check (verified)
```
app.js OK
profiles.js OK
supabase-client.js OK
config OK
```
สรุป: ไม่มี syntax error ในไฟล์ JS ทั้งหมด

### Local server (verified)
```
index index: HTTP 200 size=44203
app.js:    HTTP 200 size=329618
```
สรุป: แอปโหลดผ่าน static server ได้จริง

### สิ่งที่ยังตรวจไม่ได้ (not verified)
- **Runtime behavior ของ Edge Functions** — ต้องใช้ Deno + env จริง; ไม่มีในสภาพแวดล้อมนี้และไม่ควรตั้ง secret จริง
- **RLS/RPC behavior** — ต้องมี Supabase instance สำหรับทดสอบ (แนะนำสร้าง project ทดสอบแยก ดู `09`)
- **UI end-to-end** — ตรวจด้วยตาโค้ดแล้ว แต่ไม่ได้รัน headless browser ในรอบนี้

## Baseline ที่ตั้งได้ (reproducible)

1. เปิดไฟล์: `cd <repo>; python3 -m http.server 4173` แล้วเปิด `http://localhost:4173`
2. บัญชีทดสอบ (จาก README/seed): `ADMIN/1234`, `STAFF-01/1234`, `STAFF-02/1234`, `A-0201/1234`
3. ตรวจ syntax ก่อน commit: `node --check app.js` (WORK-LOCK-NO-UX-UI.md บรรทัด 120 กำหนดไว้แล้ว)

## ช่องว่าง baseline ที่ควรปิด (ก่อนพัฒนาต่อ)

- เพิ่ม `.gitignore` (อย่างน้อยกัน `config.js` ที่มีค่า secret จริง, `node_modules`, ไฟล์ media/localStorage dump)
- เพิ่ม `package.json` เบา ๆ เพื่อผูก script: `lint`, `check`, `test`, `serve`
- เพิ่ม lint (ESLint) + smoke test ขั้นต่ำ (ดู `08`)
- เพิ่ม `deno.json` + `deno check` สำหรับ Edge Functions
