# Profile, PIN and Interface Onboarding

เอกสารนี้อธิบาย flow หลัง login ของ Juristic Care V2:

```text
UNAUTHENTICATED
  -> AUTHENTICATED_NO_PROFILE
  -> PROFILE_SELECTED_PIN_REQUIRED
  -> PROFILE_PIN_VERIFIED
  -> INTERFACE_SELECTION_REQUIRED
  -> APPLICATION_READY
```

## Current Architecture

- Login form อยู่ใน `index.html`
- Authentication หลักอยู่ใน `app.js`
- Supabase Auth adapter อยู่ใน `supabase-client.js`
- Profile/PIN gate อยู่ใน `profiles.js`
- Full interface ใช้ `#appView`
- Compact interface ใช้ `#compactAppView`
- Interface picker อยู่ใน `app.js`
- Demo/local session ใช้ `sessionStorage`
- Demo/local profile fallback ใช้ `localStorage`

เมื่อ `SUPABASE_ENABLED: false` ระบบทำงานแบบ demo fallback เพื่อ Pre-Production UAT เท่านั้น ไม่เหมาะกับข้อมูลจริง

## Implemented Flow

1. Login ด้วย User ID และ password
2. หลัง login สำเร็จ ระบบไม่เข้า dashboard ทันที
3. ระบบแสดง Choose Profile
4. ทุก account จะมี Owner profile อัตโนมัติใน fallback migration
5. Owner แสดงเป็นรายการแรก
6. ผู้ใช้สามารถเพิ่ม Tenant / Resident ได้เมื่อมีสิทธิ์
7. เมื่อเลือก profile ระบบออก temporary 6-digit PIN
8. PIN มีอายุ 5 นาที, ใช้ได้ครั้งเดียว, ผิดได้สูงสุด 5 ครั้ง
9. หลัง verify PIN สำเร็จ ระบบเข้าสู่ Interface Selection
10. ผู้ใช้เลือก `FULL` หรือ `COMPACT`
11. ระบบบันทึก preference และเข้าสู่แอป
12. รอบ login ถัดไป restore interface เดิม ถ้ามี preference แล้ว
13. ผู้ใช้เปลี่ยน interface ภายหลังได้จากเมนูบัญชี

## Backend Migration

Migration:

```text
supabase/migrations/202607120001_profile_onboarding_stage.sql
```

สิ่งที่เพิ่ม:

- `profile_owner_conflicts`
- `profile_pin_challenges`
- `profile_preferences`
- ขยาย `room_profiles` ด้วย:
  - `account_id`
  - `profile_type`
  - `room_number`
  - `status`
  - `updated_at`
  - `created_by`
- RPC:
  - `ensure_owner_profiles`
  - `list_account_profiles`
  - `create_account_profile`
  - `select_account_profile`
  - `issue_profile_pin_challenge`
  - `verify_profile_pin_challenge`
  - `save_interface_preference`

Owner profile enforcement:

- ถ้าไม่มี Owner ระบบสร้างให้
- ถ้ามี Owner เดียว ระบบคงไว้
- ถ้ามี Owner ซ้ำ ระบบบันทึกใน `profile_owner_conflicts`
- unique owner index จะถูกสร้างเฉพาะเมื่อไม่มี duplicate owner เพื่อไม่ทำให้ migration fail หรือลบข้อมูลเงียบๆ

## Security Decisions

- ไม่เก็บ PIN plaintext
- PIN challenge เก็บเฉพาะ hash
- PIN มีอายุ 5 นาที
- PIN ใช้ได้ครั้งเดียว
- ผิดได้สูงสุด 5 ครั้ง
- ออก PIN ใหม่ invalidate challenge เก่า
- RPC ตรวจ ownership ของ profile ทุกครั้ง
- `profile_pin_challenges` ถูก revoke client direct access
- Production config ปิด `DEV_SHOW_PROFILE_PIN`
- Pre-Production build เปิด `DEV_SHOW_PROFILE_PIN` เพื่อ UAT fake-data เท่านั้น
- Logout ล้าง authenticated session, selected profile, PIN state, และ interface session state

## Limitations

- Pre-Production public version ยังเป็น static demo/local mode ตาม `SUPABASE_ENABLED: false`
- Browser fallback ไม่ใช่ server-side secure session
- Production ต้องเปิด Supabase และใช้ RPC/session ฝั่ง backend เป็น source of truth
- ยังไม่มี real delivery provider สำหรับ PIN เช่น email หรือ LINE
- เมื่อเปิด Production ต้องปิด development PIN display เสมอ

## Manual Test

1. Login ด้วย demo account
2. เห็นหน้า Choose Profile
3. Owner profile อยู่รายการแรก
4. เพิ่ม Tenant หรือ Resident profile ได้
5. เลือก profile แล้วเข้าสู่หน้า Verify PIN
6. ใส่ PIN 6 หลักจาก development display ใน Pre-Production
7. ใส่ PIN ผิดแล้วเห็น error และ attempt เพิ่ม
8. PIN ถูกต้องแล้วไปหน้า Choose Interface Design
9. เลือก Full แล้วเห็น sidebar/full dashboard
10. Logout แล้ว login ใหม่ ระบบ restore Full
11. เปิดเมนูบัญชีแล้วกดเปลี่ยนรูปแบบหน้าจอ
12. เลือก Compact แล้วเห็น compact interface
