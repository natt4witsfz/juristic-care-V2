# Permissions And Sidebar

## Sidebar Permission

All sidebar items must exist in `permissionSidebarItems`.

Current default order:

1. Google Forms
2. ภาพรวม
3. งานของฉัน
4. งานส่วนกลาง
5. งานของลูกบ้าน
6. งบการเงิน
7. ปฏิทิน
8. งานจากG-Form
9. งานของทีมงาน
10. ห้องของฉัน
11. ระบบหลังบ้าน

`ระบบหลังบ้าน` contains:

- พนักงานและบริษัทคู่สัญญา
- ลูกบ้าน
- Organization Chart
- ประกาศ
- สิทธิ์การใช้งาน
- Log

## Action Authority

`permissionActionItems` controls powers such as:

- create job
- assign job
- manage team
- manage residents
- manage announcements
- manage organization
- manage permissions
- import/export

## Supabase Tables

- `permissions`: per-user sidebar/action settings.
- `sidebar_preferences`: per-user sidebar order.

Admins must always retain full access to prevent lockout.
