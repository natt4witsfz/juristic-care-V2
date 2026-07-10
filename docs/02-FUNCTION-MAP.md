# Function Map

ไฟล์หลักคือ `app.js` และมี `profiles.js` เสริม resident profile gate

## Core State And Helpers

- `I18N`: Thai/English dictionary.
- `t(key, vars)`: translate user-facing text.
- `getText(value)`: read `{ th, en }` objects by current language.
- `normalizeJob(job)`: normalize old/new job shapes.
- `mediaSrc(value)`: supports old data URL and Supabase Storage metadata.
- `remoteSnapshot()`: returns app snapshot for bridge sync.
- `queueBackendSync()`: chooses Supabase sync when enabled, otherwise Apps Script/local path.

## Auth And App Bootstrap

- `authenticateAppUser(loginId, password)`: Supabase sign-in first, local fallback second.
- `showApp(user)`: sets current user, renders chrome, logs login, loads backend snapshot.
- `loadBackendSnapshot()`: loads Supabase bootstrap or Apps Script snapshot.
- `upsertRuntimeUser(user)`: inserts/updates runtime user list.

## Work Order Workflow

- `createJob(payload)`: creates local runtime job and queues backend sync.
- `assignJob(jobId, assigneeId, extra)`: assigns raw/pool job to a staff account.
- `validateStatusUpdate(job, payload)`: validates status, PIN, required dates, attachments.
- `updateJobStatus(jobId, payload)`: changes job status and appends timeline.
- `verifyCompletion(jobId)`: closes no-PIN jobs after authorized verification.
- `addJobTimeline(jobId, log)`: immutable-ish timeline append in runtime state.

## Permission And Sidebar

- `permissionSidebarItems`: all sidebar keys controlled by permission center.
- `permissionActionItems`: action-level authority keys.
- `hasSidebarAccess(view, user)`: checks sidebar access.
- `hasActionPermission(key, user)`: checks action authority.
- `saveUserPermissions(userId)`: saves permission override and syncs backend.
- `saveSidebarOrder()`: saves per-user sidebar order and syncs backend.

## Logs

- `addLog(action, detail, actor)`: routes log to admin/staff/resident arrays.
- `allLogs()`: merges all visible log arrays.
- `renderLogFilters()`: renders Excel-like filters.
- `matchesLogFilters(log)`: date/department/person filter logic.

## Uploads

- `fileToDataUrl(file, kind, ownerId)`: legacy name; now uploads to Supabase when enabled and falls back to data URL.
- `uploadStoredMedia(file, dataUrl, kind, ownerId)`: maps upload kind to bucket.
- `attachmentHtml(job)`: renders legacy and Supabase media.
- `announcementFirstPage(item)`: renders legacy and Supabase announcement media.
