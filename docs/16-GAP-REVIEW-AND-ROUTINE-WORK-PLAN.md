# Gap Review And Routine Work Implementation Plan

วันที่จัดทำ: 2026-07-09
สถานะ: Proposal สำหรับรีวิว ยังไม่เริ่มแตะโค้ด
ผู้เกี่ยวข้อง: Tech/System Director review

เอกสารนี้มี 3 ส่วน: (A) ผลรีวิวระบบปัจจุบันและจุดที่ขาด (B) การออกแบบระบบ Routine Work / Auto-assignment (C) แผนการ Implement แบบไม่กระทบระบบเดิม

---

## Part A: ผลการรีวิวระบบปัจจุบัน

### A1. สิ่งที่ระบบมีแล้วและอยู่ในสภาพดี

| ส่วน | สถานะ | หมายเหตุ |
| --- | --- | --- |
| Work Order lifecycle (สร้าง/มอบหมาย/อัปเดตสถานะ/PIN/verify) | ครบ | `createJob`, `assignJob`, `updateJobStatus`, `verifyCompletion` ใน `app.js` |
| ตรวจเวลางานซ้อน | มีระดับ job-vs-job | `checkScheduleConflict` เทียบเฉพาะงานที่มี `startTime` วันเดียวกัน |
| Permission Center + Sidebar per-user | ครบ | `permissionSidebarItems`, `permissionActionItems` |
| Log / Audit (admin, staff, resident) | ครบฝั่ง runtime | production ต้องผ่าน `append_audit_log` |
| ทะเบียนลูกบ้าน 882 ห้อง + CSV | ครบ | |
| Supabase schema + RLS + Edge Functions | เขียนแล้ว ยังไม่เปิดใช้ | `SUPABASE_ENABLED=false` ใน `config.js` |
| เอกสารกำกับ 15 ฉบับ + Work Lock | ดีมาก | ช่วยลดความเสี่ยงตอนแก้โค้ด |

### A2. Gap ที่พบ (เรียงตามความสำคัญ)

**G1 — ไม่มีระบบงานประจำ / Routine Work / PM เลย** (จุดที่ผู้ใช้ต้องการ)
ระบบปัจจุบันเป็น reactive ทั้งหมด: งานเกิดจากคนพิมพ์สร้าง (WebApp/G-Form) เท่านั้น ไม่มีการ generate งานตามตารางเวลา ไม่มี template งานแม่บ้าน/PM ช่าง ไม่มี flow ตรวจรับงานโดยหัวหน้า → ออกแบบใน Part B

**G2 — ไม่มีระบบล็อคช่วงเวลาส่วนตัว (Time Block)**
`checkScheduleConflict` เช็คได้เฉพาะงานชนงาน แต่ช่างล็อคเวลาสำหรับจดมิเตอร์/PM ล่วงหน้าไม่ได้ นิติจึงไม่เห็นว่าช่วงไหนไม่ควรมอบงาน Service → ออกแบบใน Part B (ใช้ตาราง `work_time_blocks` ร่วมกับ Routine)

**G3 — แนบได้เฉพาะรูปภาพ ไม่รองรับวิดีโอ**
input ทุกจุดเป็น `accept="image/*"` และ bucket `job-attachments` จำกัด 5 MB ซึ่งเล็กเกินไปสำหรับวิดีโอ PM → ต้องเพิ่ม bucket ใหม่ + UI ถ่ายวิดีโอ (Part B, Phase 4)

**G4 — ยังไม่ได้เปิดใช้ Supabase จริง**
ทุกอย่างยังอยู่บน localStorage + Apps Script bridge ระบบ Routine ต้องมี server-side scheduler จึง **ต้องเปิด Supabase ก่อนหรือพร้อมกับ Phase 1** มิฉะนั้นงานอัตโนมัติจะ generate ได้เฉพาะตอนมีคนเปิดเว็บ (ไม่น่าเชื่อถือ)

**G5 — `save_client_snapshot` bridge เป็นความเสี่ยง**
เอกสาร `12-SECURITY-MODEL.md` ระบุไว้แล้ว snapshot ทั้งก้อนจาก client เขียนทับข้อมูลได้ ควรทยอยลดบทบาทลง โดยเฉพาะข้อมูล Routine **ห้าม** ผ่าน snapshot ให้เขียนผ่าน RPC เท่านั้น

**G6 — ไม่มีระบบแจ้งเตือน (Notification)**
เมื่อ generate งานอัตโนมัติแล้ว ถ้าไม่มีการเตือน พนักงานต้องเปิดแอปเองตลอด แนะนำเพิ่มภายหลัง (LINE Messaging API ผ่าน Edge Function) — ไม่ blocking แต่ควรอยู่ใน roadmap

**G7 — จุดเสริมอื่น ๆ (ไม่เร่งด่วน)**
ปฏิทินยังเป็น mockup, งบการเงินยังเป็น mock, ไม่มี automated test (มีแค่ `node --check`), ไม่มี offline handling สำหรับแม่บ้าน/ช่างที่สัญญาณอ่อนในบางชั้น/ห้องเครื่อง, ไม่มีโมดูลจดมิเตอร์แบบเก็บตัวเลขเป็นข้อมูล (ตอนนี้ทำได้แค่แนบรูป)

**G8 — UI ของ Job Detail Modal (หลังมอบหมายงาน) ดูแข็ง ไม่น่าใช้** (feedback จากผู้ใช้ — ถือเป็นคำขอเปลี่ยน UX/UI แบบ explicit ตามกฎ Work Lock)
ปัญหาที่เห็น: ฟอร์ม `คัดแยกและมอบหมายงาน` และ `อัปเดตงาน` เป็น input/dropdown เปลือย ๆ เรียงต่อกันไม่มีลำดับชั้นสายตา, ปุ่มเขียวเต็มความกว้าง 2 ปุ่มหน้าตาเหมือนกันทำให้สับสนว่าปุ่มไหนทำอะไร, ส่วนมอบหมายงานยังแสดงอยู่ทั้งที่งานถูกมอบหมายไปแล้ว, Timeline เป็นตารางข้อความล้วนอ่านยาก, ช่องหมายเหตุ/label จัดวางไม่สม่ำเสมอ → แผนแก้อยู่ใน Phase 7 (Part C)

---

## Part B: การออกแบบระบบ Routine Work / Auto-assignment

### B1. Concept

หัวใจคือแยก "แม่แบบงาน" ออกจาก "งานที่เกิดขึ้นจริงในแต่ละรอบ":

```
routine_templates (แม่แบบ: ทำอะไร ที่ไหน เวลาไหน ถี่แค่ไหน ใครทำ ใครตรวจ ต้องมีหลักฐานอะไร)
        │  generate อัตโนมัติทุกคืนโดย scheduler ฝั่ง server
        ▼
routine_occurrences (งานจริงของวันนั้น ๆ: ผู้รับผิดชอบ สถานะ รูปก่อน/หลัง เวลาส่ง ผลตรวจ)
        │  พนักงานส่งงาน (submit)
        ▼
Review Board (หน้ารวมตรงกลาง: หัวหน้า/ผจก.อาคาร ตรวจ อนุมัติ/ตีกลับ)
        │
        ▼
Daily Summary Report (สรุปประจำวัน: ทำครบ/ขาด/ตีกลับ/เลยเวลา)
```

ตัวอย่างที่ผู้ใช้ให้มา map เป็น template ได้ตรง ๆ:

- แม่บ้าน A: "เก็บขยะห้องขยะชั้น 1–8" ทุกวัน 08:00–09:00, ต้องมีรูป before + after ต่อจุด, ผู้ตรวจ = ผจก.อาคาร
- ช่าง B: "PM ปั๊มน้ำรายเดือน" ทุกวันที่ 1 ของเดือน 10:00–12:00, ต้องมีวิดีโอการทำงานของระบบ + รูป, ผู้ตรวจ = หัวหน้าช่าง, ล็อคเวลาอัตโนมัติ (นิติมอบงาน Service ช่วงนี้ไม่ได้)
- ช่าง C: "จดมิเตอร์น้ำ/ไฟ" ทุกวัน 13:00–15:00, checklist ต่อชั้น, ล็อคเวลาอัตโนมัติ

### B2. Database Schema (ใหม่ทั้งหมด — additive เท่านั้น ไม่ ALTER ตารางเดิม)

```sql
-- แม่แบบงานประจำ
create table if not exists public.routine_templates (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  department text not null,             -- 'maid' | 'technician' | 'security' | 'gardener'
  task_type text not null,              -- 'routine' | 'pm' | 'meter_reading'
  frequency text not null,              -- 'daily' | 'weekly' | 'monthly' | 'yearly'
  by_weekdays int[] default null,       -- weekly: [1..7]
  by_monthday int default null,         -- monthly: วันที่ของเดือน
  by_month int default null,            -- yearly: เดือน
  window_start time not null,           -- เช่น 08:00
  window_end time not null,             -- เช่น 09:00
  location jsonb not null default '{}', -- { building, floors[], zone, note }
  checklist jsonb not null default '[]',-- [{ key, label_th, label_en, requires_value }]
  proof_requirements jsonb not null default
    '{"before_photo":true,"after_photo":true,"video":false,"min_photos":1,"max_photos":3}',
  assignee_mode text not null default 'fixed', -- 'fixed' | 'rotation' | 'pool'
  assignee_ids uuid[] default null,
  reviewer_ids uuid[] default null,     -- ผจก.อาคาร / หัวหน้าช่าง
  auto_time_block boolean not null default false, -- สร้าง work_time_block อัตโนมัติ
  grace_minutes int not null default 30,          -- เกินแล้วนับ late
  active boolean not null default true,
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- งานจริงของแต่ละรอบ (generate จาก template)
create table if not exists public.routine_occurrences (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.routine_templates(id) on delete cascade,
  occurrence_date date not null,
  window_start time not null,
  window_end time not null,
  assignee_id uuid references public.app_users(id),
  status text not null default 'pending',
  -- pending | in_progress | submitted | approved | rework | missed | cancelled
  checklist_results jsonb not null default '[]', -- รวมค่ามิเตอร์กรณี meter_reading
  submit_note text,
  submitted_at timestamptz,
  reviewed_by uuid references public.app_users(id),
  reviewed_at timestamptz,
  review_note text,
  rework_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, occurrence_date)
);

-- ไฟล์หลักฐาน แยก phase ก่อนทำ/หลังทำ และรองรับวิดีโอ
create table if not exists public.routine_media (
  id uuid primary key default gen_random_uuid(),
  occurrence_id uuid not null references public.routine_occurrences(id) on delete cascade,
  phase text not null,                  -- 'before' | 'after' | 'during'
  media_type text not null,             -- 'image' | 'video'
  bucket text not null,                 -- 'routine-photos' | 'routine-videos'
  object_path text not null,
  original_name text,
  mime_type text,
  size_bytes bigint,
  uploaded_by uuid references public.app_users(id),
  created_at timestamptz not null default now()
);

-- ช่วงเวลาที่ถูกล็อค (จาก routine หรือช่างล็อคเอง) — ใช้กับ G2 ด้วย
create table if not exists public.work_time_blocks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  source text not null default 'manual',   -- 'manual' | 'routine_template'
  template_id uuid references public.routine_templates(id) on delete cascade,
  block_date date,                          -- ล็อคเฉพาะวัน (null = ใช้ recurrence)
  by_weekdays int[] default null,           -- ล็อคประจำสัปดาห์
  start_time time not null,
  end_time time not null,
  reason text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
```

Storage buckets ใหม่ (private เหมือนเดิม): `routine-photos` (5 MB), `routine-videos` (แนะนำ 100 MB, จำกัดความยาวคลิปที่ UI ~60–90 วินาที)

RLS แนวเดียวกับ `jobs`: assignee เห็น/อัปเดต occurrence ของตัวเอง, reviewer + admin/co-admin เห็นทั้งแผนก, template จัดการได้เฉพาะ admin/co-admin/ผู้มีสิทธิ์ `manageRoutines` (action permission ใหม่)

### B3. RPC ใหม่ (ห้ามผ่าน `save_client_snapshot`)

- `generate_routine_occurrences(p_date date)` — สร้างงานของวันนั้นจากทุก template ที่ active + resolve ผู้รับผิดชอบ (fixed/rotation/pool) + สร้าง time block, เป็น idempotent (unique constraint กันสร้างซ้ำ)
- `start_routine_occurrence(p_id uuid)` — พนักงานกดเริ่มงาน + แนบรูป before แล้วสถานะเป็น `in_progress`
- `submit_routine_occurrence(p_id uuid, p_payload jsonb)` — ตรวจว่า proof ครบตาม `proof_requirements` ก่อนรับ (before/after/video/checklist) → `submitted`
- `review_routine_occurrence(p_id uuid, p_result text, p_note text)` — reviewer อนุมัติ (`approved`) หรือตีกลับ (`rework` + เพิ่ม `rework_count`)
- `mark_missed_occurrences(p_date date)` — ปิดงานค้างเมื่อวานเป็น `missed`
- `check_time_block_conflict(p_user uuid, p_date date, p_start time, p_end time)` — ให้ฝั่งสร้าง/มอบหมายงาน Service เรียกเช็ค

Scheduler: ใช้ `pg_cron` (มีใน Supabase) ตั้ง 2 งาน:

```
00:05 ทุกวัน → select generate_routine_occurrences(current_date);
00:10 ทุกวัน → select mark_missed_occurrences(current_date - 1);
```

สำรอง: Edge Function `routine-scheduler` เรียกจาก external cron ได้ถ้าไม่ต้องการ pg_cron

### B4. Frontend (ไฟล์ใหม่ `routines.js` — ไม่แก้ logic เดิมใน `app.js`)

เมนูใหม่ 3 รายการ (ทุกตัวต้องลงทะเบียนใน `permissionSidebarItems` ตามกฎ `05-PERMISSIONS-SIDEBAR.md`):

1. **`งานประจำ` (routineMy)** — สำหรับแม่บ้าน/ช่าง: การ์ดงานวันนี้เรียงตามช่วงเวลา, ปุ่ม `เริ่มงาน` → ถ่ายรูป before, ทำงาน, ถ่ายรูป after (+วิดีโอถ้า template บังคับ), กรอก checklist/ค่ามิเตอร์, กด `ส่งงาน` (ใช้ระบบประทับชื่อ+timestamp บนรูปที่มีอยู่แล้วผ่าน `fileToDataUrl`/`uploadStoredMedia` เดิม)
2. **`ตรวจงานประจำ` (routineReview)** — หน้ารวมตรงกลางสำหรับ ผจก.อาคาร/หัวหน้าช่าง: ตารางวันนี้ group ตามแผนก → template, เห็นสถานะทุกงาน (รอทำ/กำลังทำ/ส่งแล้ว/อนุมัติ/ตีกลับ/ขาดส่ง), เปิดดูรูปเทียบ before–after ข้างกัน, ปุ่มอนุมัติ/ตีกลับพร้อมเหตุผล, badge จำนวนงานรอตรวจ
3. **`ตั้งค่างานประจำ` (routineTemplates)** — สำหรับ admin/co-admin: CRUD template, กำหนดความถี่/ช่วงเวลา/ผู้ทำ/ผู้ตรวจ/proof/ล็อคเวลาอัตโนมัติ

จุดเชื่อมกับของเดิม (แก้น้อยที่สุด แก้เฉพาะจุด):

- `checkScheduleConflict` เพิ่มการ concat ผลจาก time blocks ต่อท้ายผลเดิม (ครอบด้วย feature flag) — นิติจะเห็นคำเตือน "ช่วงเวลานี้ช่างติดงานประจำ/PM" ตอนมอบงาน Service ด้วย confirm dialog เดิมที่มีอยู่แล้ว
- Dashboard เพิ่มการ์ดสรุป routine ของวันนี้ (render เพิ่ม ไม่แก้ของเดิม)
- ปฏิทิน: แสดง occurrence + time block ของตัวเอง (อ่านอย่างเดียว)
- i18n: string ใหม่ทั้งหมดลง `I18N.th` / `I18N.en` ตามกฎ Work Lock

### B5. State machine ของ occurrence

```
pending ──เริ่มงาน+รูปbefore──▶ in_progress ──ส่งงาน(proofครบ)──▶ submitted
   │                                                    │
   │ เลยเวลา+grace                          reviewer ──▶ approved (จบ)
   ▼                                                    └▶ rework ──▶ in_progress (วนใหม่)
 missed (จบ, ขึ้นรายงาน)
```

ทุก transition เขียน `append_audit_log` — สอดคล้องแนว audit เดิม

---

## Part C: Implementation Plan (แบ่ง Phase, ไม่ทำระบบเดิมพัง)

### หลักป้องกันระบบเดิมพัง (ตอบข้อกังวลโดยตรง)

1. **Additive-only**: migration ใหม่แยกไฟล์ (`202607xxxx_routine_work.sql`) สร้างแต่ตาราง/RPC/bucket ใหม่ ไม่ `ALTER` ตารางเดิมแม้แต่คอลัมน์เดียว → rollback = drop ตารางใหม่ จบ
2. **Feature flag**: `ROUTINES_ENABLED: false` ใน `config.js` — ปิดอยู่ = ระบบเหมือนเดิม 100% เปิดเป็นรายสภาพแวดล้อม (dev ก่อน → pilot → production)
3. **โมดูลแยกไฟล์**: โค้ดใหม่อยู่ใน `routines.js` (+ section ใหม่ท้าย `styles.css`) จุดแตะ `app.js` มีแค่ ~3 จุด: ลงทะเบียน sidebar, hook `checkScheduleConflict`, การ์ด dashboard — ทุกจุดครอบ flag
4. **ไม่ยุ่ง Work Order flow เดิม**: routine ใช้ตาราง/สถานะ/RPC ของตัวเอง ไม่ปนกับ `jobs` (เลี่ยงการ normalize สถานะข้ามชนิดงานซึ่งเป็นจุดพังคลาสสิก)
5. **ทุก Phase จบด้วย QA checklist เดิม**: `node --check`, mojibake check, smoke test ตาม `10-QA-CHECKLIST.md` + เพิ่ม routine smoke test
6. **Pilot จริง 1 template ก่อน**: เปิดใช้กับงานเก็บขยะแม่บ้าน 1 งานประมาณ 1 สัปดาห์ ก่อน roll out ทุกแผนก

### Phase 0 — เตรียมความพร้อม (0.5 สัปดาห์)

- Backup localStorage + export CSV ตาม `15-DATA-MIGRATION-CHECKLIST.md`
- สร้าง branch แยกใน repo, เพิ่ม `ROUTINES_ENABLED: false`
- **ตัดสินใจ**: เปิด Supabase production (G4) ก่อนหรือพร้อม Phase 1 — จำเป็นเพราะ scheduler ต้องรันฝั่ง server
- Acceptance: ระบบเดิมทำงานเหมือนเดิมทุกอย่าง

### Phase 1 — Schema + Scheduler (1 สัปดาห์)

- Migration ใหม่: 4 ตาราง + RLS + RPC 6 ตัว + buckets 2 ตัว + pg_cron 2 jobs
- ทดสอบ `generate_routine_occurrences` ตรง ๆ ใน SQL editor: daily/weekly/monthly/yearly, rotation, กันสร้างซ้ำ
- Acceptance: generate ถูกต้องทุก frequency, รันซ้ำไม่เกิดงานซ้ำ, ตารางเดิมไม่ถูกแตะ

### Phase 2 — งานแม่บ้าน: หน้า `งานประจำ` (1–1.5 สัปดาห์)

- `routines.js`: view รายการงานวันนี้, flow เริ่มงาน → รูป before → รูป after → ส่งงาน
- Validate proof ฝั่ง client + ฝั่ง RPC (double validation)
- Acceptance: แม่บ้าน login เห็นเฉพาะงานตัวเอง, ส่งงานไม่ได้ถ้ารูปไม่ครบ, รูปมี stamp ชื่อ+เวลา

### Phase 3 — Review Board + รายงานประจำวัน (1 สัปดาห์)

- หน้า `ตรวจงานประจำ`: ตารางรวม, before–after เทียบกัน, อนุมัติ/ตีกลับ, rework loop
- สรุปประจำวัน: ทำครบ n/m, missed, rework — แสดงบน dashboard ของ reviewer (ภายหลังต่อ export CSV ได้)
- Acceptance: ตีกลับแล้วงานกลับไปหน้าแม่บ้านพร้อมเหตุผล, งานขาดส่งขึ้น missed อัตโนมัติ, ทุก action ลง audit log

### Phase 4 — ช่าง: PM + วิดีโอ + จดมิเตอร์ (1 สัปดาห์)

- Template PM รายวัน/สัปดาห์/เดือน/ปี (โครงสร้างรองรับแล้วตั้งแต่ Phase 1)
- อัดวิดีโอ: `accept="video/*" capture="environment"` + bucket `routine-videos` + เช็คขนาด/ความยาวก่อน upload
- `task_type='meter_reading'`: checklist แบบกรอกตัวเลข เก็บใน `checklist_results` (เป็นฐานข้อมูลมิเตอร์ย้อนหลังในอนาคต)
- Acceptance: PM รายเดือน generate ถูกวัน, วิดีโอเปิดดูได้จาก review board, ค่ามิเตอร์ถูกเก็บเป็นตัวเลข

### Phase 5 — Time Block + เชื่อมระบบมอบหมายงานเดิม (0.5–1 สัปดาห์)

- ช่างล็อคเวลาเองได้จากหน้า `งานประจำ` (manual block), template ที่ตั้ง `auto_time_block` สร้าง block อัตโนมัติ
- Hook `checkScheduleConflict`: นิติมอบงาน Service ทับช่วง block → เจอ confirm dialog เดิมพร้อมเหตุผล
- แสดง block ในปฏิทิน
- Acceptance: มอบงานทับเวลา PM แล้วมีคำเตือน, ปิด flag แล้วพฤติกรรมเดิมกลับมา 100%

### Phase 6 — QA รวม + Pilot + Rollout (1 สัปดาห์)

- รัน QA checklist ทั้งชุด + ทดสอบบนมือถือจริง (แม่บ้าน/ช่างใช้มือถือเป็นหลัก)
- Pilot: 1 template แม่บ้าน + 1 template PM ช่าง, เก็บ feedback 1 สัปดาห์
- Rollout ทุกแผนก + อบรมการใช้งาน
- Acceptance: ผ่าน pilot โดยไม่มี regression ในระบบ Work Order เดิม

### Phase 7 — ปรับโฉม Job Detail Modal (G8) (1 สัปดาห์ — ทำขนานกับ Phase อื่นได้)

เป็นงาน **UI เท่านั้น** ไม่แตะ logic การมอบหมาย/อัปเดตสถานะ/PIN/validation ใด ๆ — แก้เฉพาะ HTML template + CSS ของ modal จึงเสี่ยงต่ำและทำคู่ขนานได้ทุกช่วง

แนวทางออกแบบใหม่:

- **Status Stepper ด้านบน**: แถบขั้นตอนแสดงว่างานอยู่จุดไหนของ lifecycle (รับเรื่อง → ตรวจสอบ → แก้ไข → ปิดงาน) แทนที่ผู้ใช้ต้องอ่านจาก dropdown
- **แสดงตามบริบท (context-aware)**: งานที่มอบหมายแล้ว ให้ยุบส่วน `คัดแยกและมอบหมายงาน` เป็นการ์ดสรุป "มอบหมายให้: นภา บริหาร · ครบกำหนด 1 ก.ค. 69" พร้อมปุ่มเล็ก `เปลี่ยนผู้รับผิดชอบ` — ไม่โชว์ฟอร์มเต็มค้างไว้
- **จัดกลุ่มเป็นการ์ด**: แยก sections ด้วยการ์ดมี heading + icon (ข้อมูลงาน / การมอบหมาย / อัปเดตสถานะ / Timeline) แทนเส้นตารางแข็ง ๆ
- **ปุ่ม action ชัดเจน**: เหลือปุ่ม primary เดียวต่อบริบท ปุ่มรองใช้ style secondary — แก้ปัญหาปุ่มเขียวเต็มความกว้าง 2 ปุ่มซ้ำกัน
- **Timeline แบบ visual**: เปลี่ยนจากตารางข้อความเป็น vertical timeline มีจุดสี/icon ตามประเภทเหตุการณ์ ชื่อคนทำ + เวลา อ่านไล่ง่าย
- **PIN card**: คงเดิมแต่ปรับให้เข้าชุดการ์ดใหม่
- **Form styling**: label ลอยหรืออยู่เหนือ input สม่ำเสมอ, input โค้งมนเข้าชุด, spacing ตาม scale เดียวกันทั้ง modal
- ใช้โทนสีสถานะเดิมตามตาราง Dashboard Status Colors ใน `WORK-LOCK-NO-UX-UI.md`
- Mobile: sections ยุบ/ขยายได้ (accordion) เพราะ modal ยาวมากบนจอเล็ก

ขั้นตอน: ทำ mockup HTML เทียบก่อน–หลังให้ดูอนุมัติก่อน → แก้เฉพาะ render function ของ modal + CSS → QA ว่า flow มอบหมาย/อัปเดต/ปิดงานด้วย PIN ทำงานเหมือนเดิมทุกกรณี

Acceptance: ทุก flow เดิมผ่าน smoke test ครบ, งานที่มอบหมายแล้วไม่โชว์ฟอร์มมอบหมายเต็ม, ผู้ใช้แยกปุ่มหลัก/รองออกจากกันได้ทันที

รวมประมาณ **5–6 สัปดาห์** (คนทำ 1 คน + ผู้ทดสอบ; Phase 7 ทำขนานได้ ไม่เพิ่มเวลารวมมาก)

### สิ่งที่แนะนำทำต่อหลังจบ (Backlog)

1. Notification ผ่าน LINE Messaging API (Edge Function) — เตือนงานใกล้ถึงเวลา/งานรอตรวจ (G6)
2. รายงานมิเตอร์รายเดือน + กราฟการใช้น้ำ/ไฟจากข้อมูล `meter_reading`
3. ลดบทบาท `save_client_snapshot` ตามแผนเดิม (G5)
4. Offline queue สำหรับจุดอับสัญญาณ (ห้องเครื่อง/ชั้นใต้ดิน)
5. เชื่อมปฏิทินจริง (Google Calendar) ฝั่ง server

### ตารางความเสี่ยงหลัก

| ความเสี่ยง | ผลกระทบ | การป้องกัน |
| --- | --- | --- |
| แก้ `app.js` แล้วกระทบ flow เดิม | สูง | จุดแตะ 3 จุด + flag + `node --check` + smoke test ทุก Phase |
| Scheduler ไม่รัน งานไม่ถูกสร้าง | กลาง | pg_cron + ปุ่ม manual generate สำหรับ admin + log การรันทุกครั้ง |
| วิดีโอไฟล์ใหญ่ อัปโหลดช้า/เต็ม storage | กลาง | จำกัดความยาว/ขนาดที่ UI, bucket แยก, ตรวจ quota รายเดือน |
| แม่บ้าน/ช่างไม่ถนัดแอป | กลาง | UI การ์ดใหญ่ ปุ่มน้อย ขั้นตอนเดียวต่อจอ + อบรมช่วง pilot |
| ข้อมูล routine ปนกับ snapshot bridge | สูง | ห้ามใส่ตาราง routine ใน `save_client_snapshot`/`get_app_bootstrap` snapshot — ใช้ RPC ตรงเท่านั้น |
