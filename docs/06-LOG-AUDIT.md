# Log And Audit

## Runtime Behavior

`addLog(action, detail, actor)` creates a log entry with:

- `id`
- `at`
- `actor`
- `actorId`
- `actorRoom`
- `actorRole`
- `actorDepartment`
- `action`
- `detail`

The UI combines admin, staff, and resident logs into one `Log` page.

## Filters

Log filters support:

- date range
- department multi-select
- person/room multi-select
- search inside dropdown filters

## Backend Direction

Use `audit_logs` as append-only production audit trail.

Rules:

- no client update
- no client delete
- insert through `append_audit_log` or trusted Edge Function
- admin/co-admin can view broad logs
- resident should only view logs related to self/room when exposed
