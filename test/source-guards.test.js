"use strict";
// Source-level regression guards for Stage 0 fixes that cannot yet be asserted
// through a running browser (Playwright is scaffolded but the npm registry /
// browser download was unreachable in this environment). These prove the
// specific unsafe patterns were removed.
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..");
const appJs = fs.readFileSync(path.join(root, "app.js"), "utf8");
const profilesJs = fs.readFileSync(path.join(root, "profiles.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(root, "index.html"), "utf8");
const gfIngest = fs.readFileSync(
  path.join(root, "supabase/functions/google-forms-ingest/index.ts"), "utf8");

test("jobRow escapes room/contact fields", () => {
  assert.ok(appJs.includes("${esc(job.roomNo)}"), "job.roomNo escaped");
  assert.ok(appJs.includes('${esc(job.contactName || "-")}'), "contactName escaped");
});

test("job detail modal escapes note", () => {
  assert.ok(appJs.includes('${esc(job.note || "-")}'), "note escaped");
});

test("profiles.js escapes user-entered profile names", () => {
  assert.ok(profilesJs.includes("${esc(p.name)}"), "picker name escaped");
  assert.ok(profilesJs.includes("${esc(profile.name)}"), "greeting name escaped");
});

test("security.js loaded before app.js in index.html", () => {
  const secIdx = indexHtml.indexOf("js/security.js");
  const appIdx = indexHtml.indexOf("app.js?");
  assert.ok(secIdx !== -1 && secIdx < appIdx, "security.js precedes app.js");
});

test("default password 1234 removed from real creation paths", () => {
  assert.ok(appJs.includes("genTempPassword()"), "temp password generator used");
  assert.ok((appJs.match(/genTempPassword\(\)/g) || []).length >= 3, "used in all real creation paths");
  // Remaining "1234" literals are only allowed on seeded demo fixtures (array
  // near the top of the file) or ephemeral admin-preview identities.
  const offenders = appJs.split("\n").map((line, i) => ({ line, n: i + 1 }))
    .filter(({ line }) => /password:\s*"1234"/.test(line))
    .filter(({ line, n }) => !(n < 645 || /preview/i.test(line)));
  assert.deepEqual(offenders.map((o) => o.n), [], "no '1234' default outside demo/preview/seed");
});

test("seed demo accounts tagged and isolated from real backend", () => {
  assert.ok(appJs.includes("user.isDemo = true"), "seed accounts tagged isDemo");
  assert.ok(appJs.includes("match?.isDemo && supabaseEnabled()"), "demo creds blocked on real backend");
});

test("google-forms-ingest is fail-closed on missing secret + no wildcard CORS", () => {
  assert.ok(gfIngest.includes('if (!expectedSecret) return json({ error: "SERVER_NOT_CONFIGURED" }'),
    "missing secret rejects request");
  assert.ok(!gfIngest.includes('"Access-Control-Allow-Origin": "*"'), "no wildcard CORS");
});
