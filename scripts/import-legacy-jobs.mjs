#!/usr/bin/env node
"use strict";
// Stage 5 legacy-import driver (STAGING ONLY).
//
// Security model:
//   * The service-role credential is read ONLY from the environment variable
//     SUPABASE_SERVICE_ROLE_KEY. It is never accepted on the command line,
//     never printed, never serialized into reports, logs or errors.
//   * The target project is checked against a hard allowlist containing only
//     the staging project ref; every other project is refused.
//   * Dry-run is the DEFAULT. A real write requires BOTH --commit and the
//     environment variable CONFIRM_IMPORT set to the exact --batch id.
//   * One RPC call per record (per-record transaction, per contract §8).
//   * No notification side effects: this script only calls the import RPC.
//
// Usage:
//   node scripts/import-legacy-jobs.mjs [--file scripts/legacy-sample-jobs.json]
//                                       [--batch <uuid>] [--commit]
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, CONFIRM_IMPORT (commit only)

import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";

const STAGING_PROJECT_ALLOWLIST = ["wdqadjikpkclmihbnfgg"];

function fail(msg) {
  console.error(`ABORT: ${msg}`);
  process.exit(1);
}

// --- argument parsing (credentials on argv are refused outright) ------------
const args = process.argv.slice(2);
for (const a of args) {
  if (/eyJ[A-Za-z0-9_-]{20,}/.test(a) || /^sbp?_/.test(a) || /service_role/i.test(a)) {
    fail("credentials must never be passed as command-line arguments; use the environment variable");
  }
}
function argValue(flag, fallback = null) {
  const i = args.indexOf(flag);
  return i !== -1 && args[i + 1] ? args[i + 1] : fallback;
}
const filePath = argValue("--file", "scripts/legacy-sample-jobs.json");
const commit = args.includes("--commit");
const batchId = argValue("--batch", commit ? null : randomUUID());

// --- environment -------------------------------------------------------------
const url = process.env.SUPABASE_URL || "";
const key = process.env.SUPABASE_SERVICE_ROLE_KEY || "";
if (!url || !key) fail("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in the environment");

const ref = (new URL(url).hostname.split(".")[0] || "").toLowerCase();
if (!STAGING_PROJECT_ALLOWLIST.includes(ref)) {
  fail(`project ref "${ref}" is not in the staging allowlist; refusing to run`);
}

if (commit) {
  if (!batchId) fail("--commit requires an explicit --batch <uuid>");
  if (process.env.CONFIRM_IMPORT !== batchId) {
    fail("--commit requires CONFIRM_IMPORT to equal the exact --batch id");
  }
}

// --- load records --------------------------------------------------------------
let records;
try {
  records = JSON.parse(readFileSync(filePath, "utf8"));
} catch (e) {
  fail(`cannot read ${filePath}: ${e.message}`);
}
if (!Array.isArray(records) || records.length === 0) fail("input file must be a non-empty JSON array");

// --- per-record RPC calls ------------------------------------------------------
async function importOne(record) {
  const res = await fetch(`${url}/rest/v1/rpc/import_legacy_job`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: key,
      Authorization: `Bearer ${key}`
    },
    body: JSON.stringify({
      p_import_batch_id: batchId,
      p_job: record,
      p_dry_run: !commit
    })
  });
  if (!res.ok) {
    // Body may echo request details; report status only — never headers/key.
    return { legacy_id: record?.id ?? null, status: "failed", reason: `HTTP_${res.status}`, pin_outcome: "no_pin" };
  }
  return res.json();
}

const results = [];
for (const record of records) {
  // sequential on purpose: deterministic report order, per-record isolation
  results.push(await importOne(record));
}

// --- reconciliation --------------------------------------------------------------
const counts = { submitted: results.length, inserted: 0, skipped_existing: 0, failed: 0 };
const failuresByReason = new Map();
for (const r of results) {
  if (r.status === "ok") counts.inserted++;
  else if (r.status === "skipped") counts.skipped_existing++;
  else {
    counts.failed++;
    const reason = r.reason || "UNKNOWN";
    if (!failuresByReason.has(reason)) failuresByReason.set(reason, []);
    failuresByReason.get(reason).push(r.legacy_id);
  }
}
const gate = counts.inserted + counts.skipped_existing === counts.submitted && counts.failed === 0;

console.log(`mode: ${commit ? "COMMIT (real import)" : "DRY-RUN (default; nothing written)"}`);
console.log(`batch: ${batchId}`);
console.log(`project ref: ${ref} (staging allowlist)`);
console.log("per-record results:");
for (const r of results) {
  console.log(`  ${r.legacy_id ?? "(no id)"} → ${r.status} | ${r.reason ?? ""} | pin: ${r.pin_outcome ?? "no_pin"}`);
}
console.log("reconciliation:", JSON.stringify(counts));
if (failuresByReason.size) {
  console.log("failures grouped by reason:");
  for (const [reason, ids] of failuresByReason) console.log(`  ${reason}: ${ids.join(", ")}`);
}
console.log(`acceptance gate (inserted + skipped_existing = submitted AND failed = 0): ${gate ? "PASS" : "FAIL"}`);
process.exit(gate ? 0 : 2);
