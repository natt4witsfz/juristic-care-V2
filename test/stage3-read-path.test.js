"use strict";
// Stage 3 — frontend relational job read path (source-level guards).
// These prove the single-authority wiring in the shipped sources: with
// SUPABASE_ENABLED=true, jobs hydrate only from list_jobs_for_current_user(),
// the snapshot bridge excludes the job domain, and a failed read fails closed.
// Live RLS/cross-session behavior is verified on staging, not claimed here.
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..");
const appJs = fs.readFileSync(path.join(root, "app.js"), "utf8");
const clientJs = fs.readFileSync(path.join(root, "supabase-client.js"), "utf8");
const configJs = fs.readFileSync(path.join(root, "config.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(root, "index.html"), "utf8");

// Extract a top-level function body by brace matching from its declaration.
// The parameter list is skipped first so a default like `(snapshot = {})`
// cannot be mistaken for the body.
function fnBody(source, name) {
  const decl = source.indexOf(`function ${name}(`);
  assert.notEqual(decl, -1, `function ${name} exists`);
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

test("Stage 3: job cache hydrates only from Supabase read RPC", () => {
  assert.ok(clientJs.includes('rpc("list_jobs_for_current_user")'),
    "provider calls the canonical read RPC");
  assert.ok(clientJs.includes("listJobs,"), "listJobs exported by provider");
  const hydrate = fnBody(appJs, "loadJobsFromSupabase");
  assert.ok(hydrate.includes("supabaseProvider.listJobs()"), "hydration uses provider.listJobs");
  assert.match(hydrate, /jobs = rows\.map\(normalizeJob\)\.filter\(Boolean\);/,
    "cache replaced atomically by assignment");
  assert.ok(!/jobs\.(push|unshift|concat)\(/.test(hydrate),
    "hydration never appends/merges (repeated bootstrap cannot duplicate)");
  // Jobs must not be fetched via direct table select.
  assert.ok(!/from\("jobs"\)/.test(clientJs), "no direct SELECT on jobs table");
});

test("Stage 3: remoteSnapshot() no longer contains a jobs field", () => {
  const snap = fnBody(appJs, "remoteSnapshot");
  assert.ok(!/\bjobs\b\s*[,:]/.test(snap), "snapshot payload has no jobs key");
});

test("Stage 3: applyBackendSnapshot ignores any snapshot jobs field", () => {
  const apply = fnBody(appJs, "applyBackendSnapshot");
  assert.ok(!apply.includes("snapshot.jobs"), "snapshot.jobs never read");
  assert.ok(!/\bjobs\s*=/.test(apply), "snapshot can never assign the jobs cache");
  assert.ok(!apply.includes("juristicJobsV2"), "snapshot can never write local jobs");
});

test("Stage 3: with app_snapshots populated, relational jobs still appear", () => {
  // Structural equivalent of the DoD check: the bootstrap path hydrates jobs
  // from the RPC and only then applies the (job-stripped) snapshot.
  const boot = fnBody(appJs, "loadBackendSnapshot");
  const hydrateIdx = boot.indexOf("loadJobsFromSupabase()");
  const applyIdx = boot.indexOf("applyBackendSnapshot(");
  assert.ok(hydrateIdx !== -1 && applyIdx !== -1 && hydrateIdx < applyIdx,
    "jobs hydrate from the RPC; snapshot applies afterwards and is job-blind");
});

test("Stage 3: stale localStorage jobs cannot override Supabase jobs", () => {
  assert.ok(appJs.includes("const jobsRelationalMode = !!window.JuristicSupabase?.isEnabled?.();"),
    "startup mode switch exists");
  assert.match(appJs, /let jobs = jobsRelationalMode\s*\?\s*\[\]/,
    "Supabase mode starts with an empty cache, not localStorage jobs");
  const save = fnBody(appJs, "saveJobs");
  assert.ok(save.includes("if (supabaseEnabled()) return;"),
    "saveJobs never persists/syncs jobs in Supabase mode");
});

test("Stage 3: legacy Apps Script sync no longer carries jobs", () => {
  const legacy = fnBody(appJs, "loadRemoteSnapshot");
  assert.ok(!legacy.includes("snapshot.jobs"), "Apps Script snapshot jobs ignored");
  assert.ok(!legacy.includes("juristicJobsV2"), "Apps Script sync cannot write local jobs");
});

test("Stage 3: a failed read fails closed (no local job authority)", () => {
  const hydrate = fnBody(appJs, "loadJobsFromSupabase");
  assert.ok(!hydrate.includes("localStorage"), "failure path never reads localStorage");
  assert.ok(!hydrate.includes("seedJobs"), "failure path never falls back to seeds");
  assert.ok(hydrate.includes("jobsLoadFailed = true"), "failure state recorded");
  assert.ok(hydrate.includes("showToast"), "user-visible error shown");
  assert.ok(hydrate.includes("loadJobsFromSupabase(attempt + 1)"), "bounded retry scheduled");
  const boot = fnBody(appJs, "loadBackendSnapshot");
  assert.match(boot, /return;\s*\}\s*loadRemoteSnapshot\(\);/,
    "Supabase mode returns before the legacy Apps Script fallback");
});

test("Stage 3: SUPABASE_ENABLED=false retains the demo/local behavior", () => {
  assert.ok(configJs.includes("SUPABASE_ENABLED: false"), "committed config stays false");
  assert.match(appJs, /:\s*\(JSON\.parse\(localStorage\.getItem\("juristicJobsV2"\)/,
    "demo mode still loads local jobs");
  assert.ok(appJs.includes("if (!jobsRelationalMode && !jobs.some("),
    "demo seed refresh preserved, guarded to demo mode");
});

test("Stage 3: no Secret Key, service_role or embedded credential in frontend files", () => {
  for (const [name, src] of [["app.js", appJs], ["supabase-client.js", clientJs],
                             ["config.js", configJs], ["index.html", indexHtml]]) {
    assert.ok(!/service_role|sb_secret|SECRET_KEY/i.test(src), `${name}: no secret-key reference`);
    assert.ok(!/eyJ[A-Za-z0-9_-]{20,}/.test(src), `${name}: no embedded JWT`);
    assert.ok(!/https:\/\/[a-z0-9]+\.supabase\.co/.test(src), `${name}: no hardcoded project URL`);
  }
  assert.ok(configJs.includes('SUPABASE_URL: ""') && configJs.includes('SUPABASE_ANON_KEY: ""'),
    "config placeholders remain empty");
});
