# WebApp Overview

`Juristic Care` เป็น WebApp สำหรับนิติบุคคลอาคารชุด ใช้จัดการงานแจ้งซ่อม งานส่วนกลาง ทีมงาน ลูกบ้าน ประกาศ สิทธิ์ และ Log

## Main Users

- `admin`: เห็นทุกเมนู จัดการผู้ใช้ สิทธิ์ งาน Log และข้อมูลหลังบ้าน
- `coadmin`: ช่วยจัดการบางส่วนตามสิทธิ์ที่ได้รับ
- `staff`: ทีมงาน เช่น นิติ ช่าง แม่บ้าน รปภ. คนสวน
- `resident`: ลูกบ้าน ดูงานของห้องและแจ้ง/ติดตามงานที่เกี่ยวข้อง

## Runtime Shape

- Static frontend, no build tool required.
- `index.html` holds DOM shell and modal containers.
- `styles.css` holds all visual styling.
- `app.js` holds most app state, rendering, workflow, permission, upload, and log logic.
- `profiles.js` adds resident room profile + PIN gate.
- `supabase-client.js` adds Supabase-first adapter while preserving local fallback.

## Production Direction

Production path is Supabase-first:

- Supabase Auth for login.
- Postgres tables for app data.
- RLS for access control.
- Private Storage buckets for uploaded files.
- Edge Functions for service-role-only operations.

LocalStorage remains a demo/dev fallback only when `SUPABASE_ENABLED=false`.
