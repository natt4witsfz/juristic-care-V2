# Security Model

## Principles

- Browser uses anon key only.
- Service role is only allowed in Edge Functions.
- RLS is enabled on every public table.
- Critical workflows use RPC.
- Audit logs are append-only.
- Storage buckets are private.

## Role Model

- Admin: full access.
- Co-Admin: broad access, limited by action authority.
- Staff: work and data according to department/assignment.
- Resident: own room/profile/work only.

## Sensitive Data

- Resident profile PIN is stored as `crypt()` hash.
- Job close PIN is stored separately in `job_close_pins`.
- Uploaded file access uses RLS and/or signed URL.
- Password creation/reset must go through Edge Function.

## Known Bridge Risk

`save_client_snapshot` exists to bridge the current static app. It should be reduced over time as direct table/RPC writes replace snapshot sync completely.
