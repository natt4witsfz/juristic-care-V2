# 07 — Performance & Reliability

## I. Performance

| ID | รุนแรง | ประเด็น | หลักฐาน |
| --- | --- | --- | --- |
| PERF-01 | Medium | รูปเก็บเป็น data URL ใน localStorage เมื่อ Supabase ปิด | `fileToDataUrl`/`uploadStoredMedia` 5385–5431; localStorage มีลิมิต ~5MB จะเต็มเร็วเมื่อมีรูปหลายงาน |
| PERF-02 | Medium | Snapshot ทั้งก้อนถูก serialize/ส่งทุกครั้งที่บันทึก | `remoteSnapshot` 1515, `queueSupabaseSync` 1593 — โตตามข้อมูล, เปลืองแบนด์วิดท์/เขียนทับ |
| PERF-03 | Medium | `get_app_bootstrap` ดึง jobs/logs/announcements ทั้งหมด ไม่มี pagination | migration 437–458 |
| PERF-04 | Low | `renderAll()` re-render ทั้งหน้าเมื่อมีการเปลี่ยนแปลงเล็กน้อย | เรียกถี่หลัง action (เช่น 3229, หลังทุก save) |
| PERF-05 | Low | โหลด Supabase SDK จาก CDN เสมอแม้ปิดใช้ | `index.html` 567 |
| PERF-06 | Low | `normalizeJob` ถูกเรียกซ้ำหลายรอบต่อ render (map ทั้ง array) | เช่น `checkScheduleConflict` 969, `getDashboardCounts` 1164 |
| PERF-07 | Low | `admin-users` reset-password ใช้ `listUsers()` ทั้งหมดเพื่อหา 1 คน | `admin-users` 90 |

**[fact]** ปริมาณผู้ใช้เป้าหมายตาม README = ~30 คน ในระดับนี้ performance ปัจจุบันยัง "พอไหว" สำหรับ pilot แต่ PERF-01/02/03 จะเป็นคอขวดเมื่อข้อมูลสะสม (งานหลายร้อย + รูป)

## Reliability / Resilience

| ID | รุนแรง | ประเด็น | หลักฐาน |
| --- | --- | --- | --- |
| REL-01 | High | ข้อมูลจริงอยู่ใน localStorage เดียว — ล้าง browser = ข้อมูลหาย ไม่มี backup | ทุก `save*` เขียน localStorage (1276–1285) |
| REL-02 | Medium | Sync failure ถูกกลืน ผู้ใช้อาจคิดว่าบันทึกแล้ว | `console.warn` 1572, 1600 |
| REL-03 | Medium | ไม่มี idempotency → retry สร้างงานซ้ำได้ | ดู `06` ข้อ 9 |
| REL-04 | Medium | ไม่มี optimistic-lock/transaction ในการแก้งานพร้อมกัน; last-write-wins ผ่าน snapshot | `remoteSnapshot` overwrite |
| REL-05 | Low | Race: debounce sync (600–700ms) อาจทับกันถ้าหลายแท็บ | `queueRemoteSync`/`queueSupabaseSync` timers |
| REL-06 | Low | ไม่มี graceful degradation เมื่อ Supabase ล่ม (fallback ไป localStorage แต่ผู้ใช้ไม่รู้สถานะ) | `loadBackendSnapshot` 1661 |

## พฤติกรรมบนเครือข่ายมือถือไม่เสถียร
- **[fact]** upload รูปทำครั้งเดียว ไม่มี retry/backoff/progress bar จริง (มีแค่ประมวลผลแล้ว await) — บนสัญญาณอ่อนอาจค้าง/ล้มเงียบ
- **[rec]** เพิ่ม upload progress, retry with backoff, และ resumable upload สำหรับรูปหลักฐาน

## External API failure handling
- **[fact]** `remoteRequest`/Supabase RPC ไม่มี timeout, retry, หรือ circuit breaker
- **[fact]** webhook ingest ไม่มี retry ฝั่งรับ (พึ่ง Google ส่งซ้ำ) และไม่มี dead-letter

## สรุปสิ่งที่ต้องทำก่อนข้อมูลจริง (reliability)
1. ย้าย source of truth ไป Supabase จริง (แก้ REL-01) — สำคัญสุด
2. แจ้งสถานะ sync ให้ผู้ใช้เห็น (แก้ REL-02/06)
3. idempotency + transaction ต่อ entity (แก้ REL-03/04)
4. ก่อน scale: pagination + เขียนต่อ record แทน snapshot (PERF-02/03)
