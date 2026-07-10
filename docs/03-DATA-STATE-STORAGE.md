# Data, State, And Storage

## Local Runtime State

`app.js` keeps runtime arrays in memory:

- `jobs`
- `adminLogs`, `staffLogs`, `residentLogs`
- `residentRooms`
- `teamOverrides`
- `customUsers`
- `deletedUserIds`
- `announcements`
- `organizationAssignments`

## LocalStorage Keys

These keys remain for demo/dev fallback:

- `juristicJobsV2`
- `juristicAdminLogs`
- `juristicStaffLogs`
- `juristicResidentLogs`
- `juristicResidentRooms`
- `juristicTeamOverrides`
- `juristicCustomUsers`
- `juristicDeletedUsers`
- `juristicBackhouseAnnouncements`
- `juristicOrganizationAssignments`
- `juristicLang`
- `juristicDashboardRange`
- `juristicCommonWorkRange`
- `juristicSidebarOrderV2:{userId}`

## SessionStorage Keys

- `juristicUser`: current runtime user id for local fallback.
- `juristicActiveProfile`: active resident room profile.
- `juristicAdminPreviewOriginal`: admin preview mode source user.

## Supabase Bridge

`supabase-client.js` provides:

- `loadAppData()` via `get_app_bootstrap`
- `saveSnapshot(snapshot)` via `save_client_snapshot`
- Direct methods for auth, uploads, permissions, sidebar order, and workflow RPCs

The bridge keeps current UI stable while the backend is migrated table-by-table.
