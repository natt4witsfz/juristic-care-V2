"use strict";
// Pending tests for behavior implemented in later stages (Amendment 2).
// Each names the stage that will activate it. They report as TODO, not failure.
const { test } = require("node:test");

// ---- Stage 1 — relational schema, RLS, direct-insert rejection ----
test.todo("Stage 1: RLS rejects direct anonymous INSERT into jobs");
test.todo("Stage 1: unauthorized user cannot SELECT another room's job (BOLA)");
test.todo("Stage 1: list_jobs_for_current_user returns only permitted jobs");
test.todo("Stage 1: import_legacy_job contract validates required fields");

// ---- Stage 2 — server-enforced workflow ----
test.todo("Stage 2: completion without valid PIN is rejected or forced to pending_inspection");
test.todo("Stage 2: no-PIN completion becomes pending_inspection + waiting_verification");
test.todo("Stage 2: required evidence (1-3 photos) enforced server-side");
test.todo("Stage 2: illegal status transition is rejected");
test.todo("Stage 2: every transition writes immutable job_timeline and audit_logs");
test.todo("Stage 2: Asia/Bangkok job date has no UTC off-by-one at midnight boundary");
test.todo("Stage 2: ingest_google_form_submission is transactional and rolls back on failure");
test.todo("Stage 2: get_app_bootstrap never serves jobs from app_snapshots");

// ---- Stage 3 — frontend relational read path ----
// Activated: see test/stage3-read-path.test.js (source-level guards). The
// live cross-session/staging behavior is validated in the Stage 3 staging
// dry-run, not claimed here.

// ---- Stage 4 — frontend record-level writes ----
// Activated: "createJob/assignJob/updateJobStatus/verifyCompletion call RPCs"
// is now covered by test/stage4-write-path.test.js (source-level guards).
test.todo("Stage 4: a WebApp-created job appears after reload in another session");

// ---- Stage 5 — legacy import & reconciliation ----
test.todo("Stage 5: duplicate (source, legacy_id) import inserts exactly one job");
test.todo("Stage 5: legacy plaintext PIN is hashed in-DB or rotated, never stored/returned plaintext");

// ---- Stage 7 — Google Form end-to-end ----
test.todo("Stage 7: duplicate external_id creates exactly one job (idempotent)");
test.todo("Stage 7: disabling the Form trigger stops new intake without affecting existing jobs");
