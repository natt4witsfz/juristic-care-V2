# Juristic Care V2 Handoff - Read Me First

วันที่จัดทำ: 2026-07-14

เอกสารชุดนี้ทำไว้สำหรับส่งต่อให้ Codex อีกบัญชีทำงานต่อใน repository:

```text
C:\Projects\juristic-care-V2
```

GitHub:

```text
https://github.com/ort83tester-arch/juristic-care-V2.git
```

## สถานะล่าสุด

- Branch: `feat/stage-5-legacy-import`
- HEAD ล่าสุด: `a8fb2b7 feat: add profile PIN onboarding flow`
- Working tree ก่อนสร้างเอกสาร handoff: clean
- Production: ห้ามแตะถ้าไม่ได้รับคำสั่งยืนยันแยกต่างหาก
- Pre-Production URL:
  `https://juristic-care-v2-preprod.mitratiwa.chatgpt.site`
- Production URL:
  `https://juristic-care-v2.mitratiwa.chatgpt.site`

## Project IDs

- Pre-Production Sites project:
  `appgprj_6a5275267d8481918257207f7d8df2f2`
- Production Sites project:
  `appgprj_6a527385dc688191abc5b6c7aa057ee3`
- Supabase Staging project ref:
  `wdqadjikpkclmihbnfgg`

## สิ่งที่ต้องรู้ทันที

1. ตอนนี้ frontend committed config ยังเป็น demo/static mode:
   `SUPABASE_ENABLED: false`
2. Pre-Production public version เป็น UAT/fake-data mode เท่านั้น
3. Production ต้องไม่ถูก deploy หรือแก้ไข หากไม่มี approval แยก
4. ห้ามขอหรือแสดง Secret Key ใน chat
5. Stage 5 legacy import dry-run เคยผ่านแล้ว แต่ห้าม real import โดยไม่มีคำสั่งแยก
6. มี Bit-code guard สำหรับ production promotion แล้ว
7. Flow ใหม่หลัง login ถูก deploy ไป Pre-Production version 5 แล้ว

## อ่านไฟล์ต่อในลำดับนี้

1. `01-CURRENT-STATE.md`
2. `02-RECENT-WORK-COMPLETED.md`
3. `03-SECURITY-AND-SECRETS.md`
4. `04-DEPLOYMENT-RUNBOOK.md`
5. `05-PREPROD-TESTING.md`
6. `06-NEXT-WORK.md`
7. `07-FILE-MAP.md`
8. `08-CODEX-PROMPT-FOR-NEXT-AGENT.md`
9. `09-UNIVERSAL-AI-CONTINUATION-PROMPT.md`

## คำสั่งเช็กก่อนทำงานต่อ

```powershell
cd C:\Projects\juristic-care-V2
git status --short
git branch --show-current
git log -5 --oneline
npm run check
npm test
```

Expected baseline ล่าสุด:

- `npm run check` ผ่าน
- `npm test` ผ่าน: 72 tests, 57 pass, 0 fail, 15 todo
