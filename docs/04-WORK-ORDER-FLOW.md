# Work Order Flow

## Sources

- WebApp create form.
- Google Forms ingest through Edge Function.
- Imported/demo seed data.

## Main Lifecycle

1. Job is created as `open` when unassigned or `received` when assigned.
2. Admin/authorized staff categorizes and assigns work.
3. Assigned work appears in `งานของฉัน` and relevant staff team board.
4. Staff updates status with required fields and attachments.
5. Completed work requires close PIN unless no-PIN flow is used.
6. No-PIN completion becomes pending verification.
7. Admin/co-admin/assigner/resident owner verifies completion.

## Important Statuses

- `open`
- `received`
- `pending_inspection`
- `inspected_waiting_repair`
- `repaired_follow_up`
- `temporary_waiting_parts`
- `waiting_owner_or_admin_verification`
- `completed`
- `rejected`

## Backend Direction

Production writes should go through RPC:

- `create_job`
- `assign_job`
- `update_job_status`
- `verify_job_completion`

Direct table updates should be limited by RLS and avoided for critical workflow steps.
