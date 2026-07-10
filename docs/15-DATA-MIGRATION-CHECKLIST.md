# Data Migration Checklist

## Before Migration

- Export current localStorage data from a trusted admin browser.
- Export resident CSV and employee CSV.
- Back up announcements/files if needed.
- Record current sidebar/permission settings.

## Migration Order

1. Create Supabase Auth users through `admin-users`.
2. Insert `rooms`.
3. Insert `app_users`.
4. Insert resident people/cars.
5. Insert jobs.
6. Insert job timeline.
7. Upload attachments to private Storage.
8. Insert permissions and sidebar preferences.
9. Insert announcements and organization assignments.
10. Verify audit log behavior.

## Acceptance

- Admin can login with current UX.
- Staff can see assigned work.
- Resident can see only own room data.
- Files are private and accessible only through allowed flow.
- Log filters still work.
- Permission Center controls sidebar/action authority.
