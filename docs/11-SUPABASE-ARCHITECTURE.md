# Supabase Architecture

## Frontend

- Static WebApp.
- Supabase JS v2 loaded from CDN.
- `supabase-client.js` owns all Supabase calls.
- `app.js` talks to the adapter and keeps existing UI rendering.

## Database

Main tables:

- `rooms`
- `app_users`
- `room_profiles`
- `jobs`
- `job_timeline`
- `job_attachments`
- `resident_people`
- `resident_cars`
- `permissions`
- `sidebar_preferences`
- `announcements`
- `organization_assignments`
- `audit_logs`
- `google_form_submissions`

## RPC

Workflow RPCs:

- `create_profile`
- `verify_profile_pin`
- `create_job`
- `assign_job`
- `update_job_status`
- `verify_job_completion`
- `append_audit_log`
- `get_app_bootstrap`
- `save_client_snapshot`

## Edge Functions

- `admin-users`: user creation/password reset with service role.
- `google-forms-ingest`: Google Forms raw ingest to job pool.
- `secure-file-access`: signed URL after permission check.
