# Juristic Care Pilot: GitHub Pages + Google Sheet/Drive

แพ็กเกจนี้ใช้สำหรับรันทดสอบก่อนซื้อ Firebase/Supabase จริง

## Architecture

```text
GitHub Pages
  - index.html
  - app.js
  - styles.css
  - config.js

Google Apps Script Web App
  - รับ action จาก WebApp
  - อ่าน/เขียน Google Sheet

Google Sheet
  - เก็บ snapshot ข้อมูล pilot

Google Drive
  - เตรียม folder สำหรับไฟล์แนบในเฟสถัดไป
```

## 1. Deploy Google Apps Script

1. เปิด https://script.google.com/
2. สร้าง New project
3. วางไฟล์ `apps-script/Code.gs`
4. กด Run ฟังก์ชัน `setup`
5. อนุญาตสิทธิ์ Google
6. ไปที่ Deploy > New deployment
7. เลือก type เป็น Web app
8. Execute as: Me
9. Who has access: Anyone with the link
10. Deploy แล้ว copy Web app URL

หมายเหตุ: ถ้าเลือกสิทธิ์แคบกว่านี้ ผู้ใช้ทั่วไปอาจเรียก API จาก GitHub Pages ไม่ได้

## 2. ตั้งค่า WebApp

เปิดไฟล์ `web/config.js` แล้วแทน:

```js
APPS_SCRIPT_URL: "PASTE_APPS_SCRIPT_WEB_APP_URL_HERE"
```

ด้วย Web app URL จาก Apps Script

## 3. Deploy GitHub Pages

1. สร้าง GitHub repository ใหม่ เช่น `juristic-care-pilot`
2. upload ไฟล์ในโฟลเดอร์ `web/` ไปไว้ root ของ repo
3. ไปที่ Settings > Pages
4. Source: Deploy from a branch
5. Branch: main / root
6. Save
7. เปิด URL ที่ GitHub Pages สร้างให้

## 4. วิธีทดสอบ

1. เปิดหน้า GitHub Pages
2. Login demo ด้วย ADMIN / 1234
3. สร้างงานใหม่
4. Refresh browser หรือเปิดอีกเครื่อง
5. Login อีกครั้ง ระบบจะโหลดข้อมูลจาก Google Sheet snapshot

## ข้อจำกัดของ Pilot นี้

- เป็น snapshot sync ไม่ใช่ realtime database
- ถ้าผู้ใช้สองคนกดแก้ไขพร้อมกันมาก ๆ อาจเกิด last-write-wins
- เหมาะกับ pilot อาคารเดียว ผู้ใช้หลักสิบ
- ยังไม่ใช่ security model ระดับ production
- File upload ไป Drive ยังควรทำเป็น endpoint แยกในเฟสถัดไป

## เมื่อควรย้ายไป Firebase/Supabase

- ต้องการ realtime จริง
- ต้องการ auth/permission แข็งแรง
- มีหลายอาคาร/หลายโครงการ
- มีไฟล์แนบจำนวนมาก
- มีข้อมูลหลักหมื่นรายการขึ้นไป

