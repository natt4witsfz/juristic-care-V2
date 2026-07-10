# Storage Uploads

## Buckets

- `job-attachments`: private, max 5 MB.
- `announcement-files`: private, max 12 MB.
- `profile-images`: private, max 5 MB.

## Frontend Flow

`fileToDataUrl(file, kind, ownerId)` now:

1. creates local preview/stamped image when needed
2. uploads to Supabase Storage when enabled
3. returns Storage metadata with a signed preview URL
4. falls back to data URL when Supabase is disabled or upload fails

## Access Rules

- job files: readable by assigned staff, assigner, admin/co-admin, or related room/resident.
- announcement files: readable by authenticated users.
- profile images: readable by owner or admin/co-admin.

## Production Improvement

Long-lived previews should eventually be resolved through `secure-file-access` at render time instead of storing signed URLs in snapshot data.
