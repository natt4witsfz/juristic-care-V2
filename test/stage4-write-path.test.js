"use strict";
// Stage 4 — frontend relational job write path (source-level guards).
// Prove that in Supabase mode every job mutation goes through the approved
// server RPC, the cache refreshes only via the read RPC, closePin stays
// isolated, M5/M6 and creation-time attachments are blocked fail-closed, and
// demo/local behavior is preserved. Live staging behavior is validated
// separately and not claimed here.
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..");
const appJs = fs.readFileSync(path.join(root, "app.js"), "utf8");

// Extract a top-level function body by brace matching, skipping the parameter
// list so defaults like `(extra = {})` cannot be mistaken for the body.
function fnBody(source, name, declPrefix = "function ") {
  const decl = source.indexOf(`${declPrefix}${name}(`);
  assert.notEqual(decl, -1, `${name} exists`);
  let i = source.indexOf("(", decl);
  for (let parens = 0; ; i++) {
    if (source[i] === "(") parens++;
    if (source[i] === ")") parens--;
    if (parens === 0) break;
    assert.ok(i < source.length, `unbalanced parameter list in ${name}`);
  }
  const open = source.indexOf("{", i);
  let depth = 0;
  for (let j = open; j < source.length; j++) {
    if (source[j] === "{") depth++;
    if (source[j] === "}") depth--;
    if (depth === 0) {
      const body = source.slice(open, j + 1);
      assert.ok(body.length > 2, `${name} body extracted`);
      return body;
    }
  }
  assert.fail(`unbalanced braces in ${name}`);
}

const facades = {
  createJob: fnBody(appJs, "createJob"),
  assignJob: fnBody(appJs, "assignJob"),
  updateJobStatus: fnBody(appJs, "updateJobStatus"),
  verifyCompletion: fnBody(appJs, "verifyCompletion")
};
const rpcByFacade = {
  createJob: "supabaseProvider.createJob(",
  assignJob: "supabaseProvider.assignJob(",
  updateJobStatus: "supabaseProvider.updateJobStatus(",
  verifyCompletion: "supabaseProvider.verifyCompletion("
};

test("Stage 4: each mutation path calls the correct RPC in Supabase mode", () => {
  for (const [name, body] of Object.entries(facades)) {
    assert.ok(body.includes(rpcByFacade[name]), `${name} calls its RPC`);
    assert.ok(body.includes(`${name}Local(`), `${name} keeps the demo/local branch`);
    assert.ok(body.includes("if (!supabaseEnabled())"), `${name} branches on mode`);
  }
});

test("Stage 4: successful mutations refresh only through loadJobsFromSupabase", () => {
  for (const [name, body] of Object.entries(facades)) {
    assert.ok(body.includes("await loadJobsFromSupabase()"), `${name} refreshes via the read RPC`);
    assert.ok(!/\bjobs\s*=/.test(body), `${name} never assigns the cache directly`);
    assert.ok(!/jobs\.(push|unshift|splice|concat)\(/.test(body), `${name} never inserts into the cache`);
  }
});

test("Stage 4: RPC return objects are not inserted into the cache", () => {
  const body = facades.createJob;
  // The result is only used to split off the one-time PIN and the id.
  assert.ok(body.includes("result?.closePin"), "closePin split from the result");
  assert.ok(!/jobs\.(push|unshift)\(.*result/.test(body), "result never pushed into jobs");
  assert.ok(!body.includes("normalizeJob(result"), "result never normalized into the cache");
});

test("Stage 4: RPC failure does not mutate the cache and shows a visible error", () => {
  for (const [name, body] of Object.entries(facades)) {
    const catchIdx = body.indexOf("catch (error)");
    assert.notEqual(catchIdx, -1, `${name} has a failure path`);
    const catchBlock = body.slice(catchIdx);
    assert.ok(/showToast\(jobMutationErrorText\(error\)\)|errors: \[jobMutationErrorText\(error\)\]/.test(catchBlock),
      `${name} failure produces a visible message`);
    assert.ok(!/\bjobs\b/.test(catchBlock.split("finally")[0]), `${name} failure path never touches the cache`);
  }
  // Bilingual error texts exist.
  const errFn = fnBody(appJs, "jobMutationErrorText");
  assert.ok(errFn.includes("Invalid close PIN") && errFn.includes("PIN ไม่ถูกต้อง"), "Thai/English errors");
});

test("Stage 4: duplicate-submit/in-flight protection works", () => {
  assert.ok(appJs.includes("const jobMutationInFlight = { create: false, assign: false, update: false, verify: false };"),
    "in-flight guard state exists");
  for (const [name, body] of Object.entries(facades)) {
    assert.match(body, /if \(jobMutationInFlight\.\w+\) return/, `${name} rejects concurrent submits`);
    assert.match(body, /finally \{\s*jobMutationInFlight\.\w+ = false;/, `${name} releases the guard on success AND failure`);
  }
  assert.ok(facades.createJob.includes("idempotencyKey:"), "create payload carries an idempotencyKey");
});

test("Stage 4: closePin never enters normalized cache, storage, snapshots or logs", () => {
  const body = facades.createJob;
  assert.ok(!/localStorage|sessionStorage/.test(body), "create facade touches no web storage");
  assert.ok(!/console\.\w+\([^)]*[Pp]in/.test(body), "PIN never passed to console");
  assert.ok(!/addLog\([^)]*[Pp]in/.test(body), "PIN never passed to app logs");
  assert.ok(!/remoteSnapshot|saveSnapshot/.test(body), "create facade never snapshots");
  // normalizeJob must not fabricate a PIN in Supabase mode.
  assert.ok(appJs.includes("if (!supabaseEnabled()) job.closePin = job.closePin || generateClosePin();"),
    "normalizeJob fabricates closePin only in demo mode");
});

test("Stage 4: M5/M6 are blocked before cache mutation in Supabase mode", () => {
  const request = fnBody(appJs, "requestOrDeleteUser");
  const guardIdx = request.indexOf("if (supabaseEnabled()) return showToast(");
  const mutateIdx = request.indexOf("jobs.unshift(");
  assert.ok(guardIdx !== -1 && mutateIdx !== -1 && guardIdx < mutateIdx,
    "requestOrDeleteUser blocks before jobs.unshift");
  assert.ok(request.includes("not yet supported in Supabase mode"), "bilingual unsupported message (EN)");
  assert.ok(request.includes("ยังไม่รองรับในโหมด Supabase"), "bilingual unsupported message (TH)");
  const del = fnBody(appJs, "deleteUserNow");
  const delGuard = del.indexOf("requestJobId && supabaseEnabled()");
  const delMutate = del.indexOf('job.deleteRequest.status = "approved"');
  assert.ok(delGuard !== -1 && delMutate !== -1 && delGuard < delMutate,
    "deleteUserNow blocks before pseudo-job mutation");
});

test("Stage 4: create with attachments is blocked before any upload or RPC call", () => {
  const handlerStart = appJs.indexOf('$("#createJobForm").addEventListener("submit"');
  assert.notEqual(handlerStart, -1, "create form handler exists");
  const handler = appJs.slice(handlerStart, appJs.indexOf("});", appJs.indexOf("showToast(t(\"toast.created\"))", handlerStart)));
  const blockIdx = handler.indexOf("supabaseEnabled() && files.length");
  const uploadIdx = handler.indexOf("fileToDataUrl(");
  const rpcIdx = handler.indexOf("await createJob(");
  assert.ok(blockIdx !== -1, "attachment block exists");
  assert.ok(uploadIdx !== -1 && blockIdx < uploadIdx, "block precedes any upload call");
  assert.ok(rpcIdx !== -1 && blockIdx < rpcIdx, "block precedes the RPC call");
  assert.ok(handler.includes("ยังไม่รองรับการแนบรูปตอนสร้างงาน"), "Thai limitation message");
  assert.ok(handler.includes("not yet supported"), "English limitation message");
});

test("Stage 4: no orphan upload path is reachable from the mutation facades", () => {
  for (const [name, body] of Object.entries(facades)) {
    assert.ok(!/uploadStoredMedia|fileToDataUrl|uploadFile\(/.test(body),
      `${name} performs no Storage upload itself`);
  }
  // Evidence mapping fails closed BEFORE the RPC on non-Storage attachments.
  const mapFn = fnBody(appJs, "mapEvidenceAttachments");
  assert.ok(mapFn.includes('throw new Error("EVIDENCE_UPLOAD_FAILED")'), "invalid evidence aborts");
  const update = facades.updateJobStatus;
  assert.ok(update.indexOf("mapEvidenceAttachments(") < update.indexOf("supabaseProvider.updateJobStatus("),
    "evidence is validated before the RPC");
});

test("Stage 4: status-update payload maps closePin to pin and respects DB-03", () => {
  const update = facades.updateJobStatus;
  assert.ok(update.includes("pin: payload.closePin"), "closePin mapped to server field pin");
  assert.ok(update.includes("objectPath:") || fnBody(appJs, "mapEvidenceAttachments").includes("objectPath:"),
    "evidence uses the approved shape");
  assert.ok(update.includes("if (payload.nextUpdateDate) rpcPayload.nextUpdateDate"),
    "nextUpdateDate key sent only when present (DB-03)");
});

test("Stage 4: demo/local behavior remains preserved", () => {
  for (const local of ["createJobLocal", "assignJobLocal", "updateJobStatusLocal", "verifyCompletionLocal"]) {
    const body = fnBody(appJs, local);
    assert.ok(body.includes("saveJobs()"), `${local} keeps the demo persistence flow`);
  }
  assert.ok(fnBody(appJs, "createJobLocal").includes("closePin: generateClosePin()"),
    "demo create still generates a local closePin");
});

test("Stage 4: startTime and endTime remain in the create payload", () => {
  const body = facades.createJob;
  assert.ok(body.includes("startTime: payload.startTime"), "startTime sent");
  assert.ok(body.includes("endTime: payload.endTime"), "endTime sent");
  // Schedule-conflict metadata is a client-side warning only, never sent as
  // persisted server authority.
  assert.ok(!/hasScheduleConflict|conflictConfirmed/.test(body),
    "conflict metadata not claimed as server authority");
});
