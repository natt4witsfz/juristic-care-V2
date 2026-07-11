"use strict";
// Stage 5 — legacy import guards (source-level + algorithm properties).
// Live database behavior (dry-run zero-write, rollback, idempotency against
// real rows) is asserted in supabase/tests/stage5_smoke.sql on staging and is
// not claimed here; these tests pin the shipped sources and the deterministic
// id algorithm.
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const root = path.join(__dirname, "..");
const migration = fs.readFileSync(
  path.join(root, "supabase/migrations/202607110001_import_legacy_job_stage5.sql"), "utf8");
const smoke = fs.readFileSync(path.join(root, "supabase/tests/stage5_smoke.sql"), "utf8");
const cleanup = fs.readFileSync(path.join(root, "supabase/tests/stage5_cleanup.sql"), "utf8");
const driver = fs.readFileSync(path.join(root, "scripts/import-legacy-jobs.mjs"), "utf8");
const sample = JSON.parse(fs.readFileSync(path.join(root, "scripts/legacy-sample-jobs.json"), "utf8"));
const code = migration.split("\n").filter(l => !/^\s*--/.test(l)).join("\n");

// JS mirror of the SQL deterministic-id algorithm (documented contract):
// 'LG-' + first 12 uppercase hex chars of sha256(lower(trim(source)) + ':' + trim(legacy_id))
const targetId = (source, legacyId) => "LG-" + crypto.createHash("sha256")
  .update(`${source.trim().toLowerCase()}:${legacyId.trim()}`)
  .digest("hex").slice(0, 12).toUpperCase();

test("Stage 5: migration/contract structure and schema-qualified pgcrypto", () => {
  assert.ok(code.includes("public.import_legacy_job("), "body implemented");
  assert.ok(!code.includes("IMPORT_UNAVAILABLE"), "Stage 1 stub removed");
  assert.ok(code.includes("security definer") && code.includes("set search_path = public"),
    "SECURITY DEFINER + fixed search_path");
  assert.ok(code.includes("coalesce(auth.role(), '') = 'service_role'")
    && code.includes("public.is_admin_account()"), "authorization guard unchanged");
  assert.ok(!code.includes("create_job("), "create_job is never used for import");
  // every pgcrypto call is schema-qualified
  const stripped = code.replace(/extensions\.(digest|crypt|gen_salt|gen_random_bytes)\(/g, "Q(");
  assert.ok(!/(^|[^.\w])(digest|crypt|gen_salt|gen_random_bytes)\(/.test(stripped),
    "no unqualified pgcrypto call");
  // migration version unique
  const versions = fs.readdirSync(path.join(root, "supabase/migrations")).map(f => f.split("_")[0]);
  assert.equal(new Set(versions).size, versions.length, "migration versions unique");
});

test("Stage 5: dry-run zero-write structure", () => {
  const dryIdx = code.indexOf("if p_dry_run then");
  const writeIdx = code.indexOf("insert into public.jobs");
  assert.ok(dryIdx !== -1 && writeIdx !== -1 && dryIdx < writeIdx,
    "dry-run returns before the write phase begins");
  const preDry = code.slice(0, dryIdx);
  assert.ok(!/insert into|update |delete from/.test(preDry),
    "no write statement exists before the dry-run return");
});

test("Stage 5: deterministic id — stability, order independence, divergence", () => {
  assert.ok(code.includes("extensions.digest(lower(btrim(p_source)) || ':' || btrim(p_legacy_id), 'sha256')"),
    "SQL algorithm matches the documented contract");
  assert.ok(!/gen_random_uuid|randomUUID|random\(\)/.test(code.match(/_legacy_job_target_id[\s\S]*?\$\$;/)[0]),
    "no randomness in id generation");
  const a1 = targetId("legacy_local_storage", "LEG-SHARED-ID");
  const a2 = targetId("legacy_local_storage", "LEG-SHARED-ID");
  assert.equal(a1, a2, "same inputs → same id (stability)");
  const b = targetId("legacy_snapshot_archive", "LEG-SHARED-ID");
  assert.notEqual(a1, b, "different source, same legacy_id → different id");
  assert.equal(targetId("  Legacy_Local_Storage ", "LEG-SHARED-ID"), a1, "source normalized");
  assert.match(a1, /^LG-[0-9A-F]{12}$/, "id shape");
  // order independence: ids computed in any processing order are identical
  const forward = sample.map(r => targetId(r.source, r.id));
  const reversed = [...sample].reverse().map(r => targetId(r.source, r.id)).reverse();
  assert.deepEqual(forward, reversed, "import order cannot affect target ids");
});

test("Stage 5: per-record rollback and safe failure vocabulary", () => {
  const writePhase = migration.slice(migration.indexOf("-- ---- WRITE PHASE"));
  assert.ok(writePhase.length > 100, "write phase marker found");
  assert.ok(/begin\r?\n[\s\S]*exception when others/.test(writePhase),
    "write phase wrapped in a nested block (per-record rollback)");
  assert.ok(code.includes("'PIN_MIGRATION_FAILED'") && code.includes("'TARGET_ID_COLLISION'"),
    "failure reasons defined");
  assert.ok(code.includes("'INVALID_STATUS'") && code.includes("'INVALID_SUB_STATUS'")
    && code.includes("'INVALID_TIMESTAMP_ORDER'"), "invalid input reasons defined");
  assert.ok(code.includes("'pseudo_job'") && code.includes("'already_imported'"),
    "skip reasons defined");
});

test("Stage 5: rotate-all PIN policy with no plaintext/hash exposure", () => {
  assert.ok(code.includes("v_pin_outcome := 'pin_rotated'"), "rotate-all outcome");
  assert.ok(code.includes("extensions.crypt(v_new_pin, extensions.gen_salt('bf'))"),
    "replacement PIN hashed in-DB");
  assert.ok(code.includes("rotated_at) ") || code.includes("rotated_at)"), "rotation recorded");
  assert.ok(code.includes("v_new_pin := null;"), "plaintext discarded after hashing");
  // the result object never carries pin values or hashes
  const results = code.match(/jsonb_build_object\('legacy_id'[\s\S]*?\)/g) || [];
  assert.ok(results.length >= 5, "per-record results found");
  for (const r of results) {
    assert.ok(!/v_new_pin|pin_hash|closePin/.test(r), "no PIN value or hash in any result");
  }
  assert.ok(!/raise notice[^;]*pin/i.test(code), "no PIN in log notices");
  const vocab = ["pin_migrated", "pin_rotated", "no_pin", "pin_migration_failed"];
  const outcomes = [...code.matchAll(/'pin_outcome',\s*'([a-z_]+)'/g)].map(m => m[1]);
  assert.ok(outcomes.length >= 5, "quoted pin outcomes found");
  for (const o of outcomes) {
    assert.ok(vocab.includes(o), `pin outcome '${o}' is in the approved vocabulary`);
  }
  // payload whitelist never copies PIN keys
  const payloadBlock = code.match(/v_payload := jsonb_strip_nulls\(jsonb_build_object\([\s\S]*?\)\);/)[0];
  assert.ok(!/closePin|'pin'|pinHash/.test(payloadBlock), "payload whitelist has no PIN keys");
});

test("Stage 5: embedded evidence fails closed; stable objectPath maps", () => {
  assert.ok(code.includes("'EVIDENCE_BINARY_MIGRATION_REQUIRED'"), "binary evidence reason");
  const classify = code.match(/_legacy_evidence_kind[\s\S]*?\$\$;/)[0];
  assert.ok(classify.includes("'binary'") && classify.includes("'stable'"), "classifier kinds");
  assert.ok(classify.includes("like 'data:%'"), "dataURL markers detected");
  const evidenceIdx = code.indexOf("EVIDENCE_BINARY_MIGRATION_REQUIRED");
  const writeIdx = code.indexOf("insert into public.jobs");
  assert.ok(evidenceIdx < writeIdx, "evidence classified before any write");
  assert.ok(code.includes("insert into public.job_attachments"), "stable refs map to job_attachments");
  assert.ok(!/storage\.objects|storage\.buckets|\.upload\(|uploadFile/i.test(code),
    "no Storage upload in the migration");
});

test("Stage 5: timeline provenance and preserved timestamps", () => {
  assert.ok(code.includes("v_tl_at, true)"), "timeline rows inserted with imported = true");
  assert.ok(code.includes("v_created, v_updated"), "created_at/updated_at preserved on the job row");
  assert.ok(!/insert into public\.job_timeline[\s\S]{0,400}'created'[\s\S]{0,100}now\(\)/.test(code),
    "no fabricated historical events");
  assert.ok(code.includes("at time zone 'Asia/Bangkok'"), "naive timestamps read as Bangkok time");
});

test("Stage 5: unresolved relationships are reported, never invented", () => {
  assert.ok(code.includes("'unresolved_reporter'") && code.includes("'unresolved_assignee'")
    && code.includes("'unresolved_assigned_by'") && code.includes("'unresolved_room'"),
    "unresolved notes recorded");
  const resolver = code.match(/_legacy_resolve_user[\s\S]*?\$\$;/)[0];
  assert.ok(!/insert into/.test(resolver), "resolver never creates users");
});

test("Stage 5: driver security controls", () => {
  assert.ok(driver.includes('STAGING_PROJECT_ALLOWLIST = ["wdqadjikpkclmihbnfgg"]'),
    "staging allowlist is exactly the approved ref");
  assert.ok(driver.includes("process.env.SUPABASE_SERVICE_ROLE_KEY"), "credential from env only");
  assert.ok(driver.includes("credentials must never be passed as command-line arguments"),
    "argv credentials refused");
  assert.ok(driver.includes("p_dry_run: !commit") && driver.includes('args.includes("--commit")'),
    "dry-run is the default; real write needs --commit");
  assert.ok(driver.includes("process.env.CONFIRM_IMPORT !== batchId"),
    "commit additionally requires CONFIRM_IMPORT === batch id");
  // the key variable is never interpolated into any output call
  for (const line of driver.split("\n")) {
    if (/console\.(log|error)/.test(line)) {
      assert.ok(!/\bkey\b/.test(line), `credential never printed: ${line.trim()}`);
    }
  }
  // No notification side effects: the only network call is the import RPC.
  const fetches = [...driver.matchAll(/fetch\(([^,]+)/g)].map(m => m[1]);
  assert.equal(fetches.length, 1, "exactly one network call in the driver");
  assert.ok(fetches[0].includes("/rest/v1/rpc/import_legacy_job"), "and it is the import RPC");
  assert.ok(driver.includes("counts.inserted + counts.skipped_existing === counts.submitted"),
    "reconciliation gate implemented exactly");
});

test("Stage 5: cleanup script fails closed", () => {
  assert.ok(cleanup.includes("'FILL-IN-IMPORT-BATCH-ID'") && cleanup.includes("'FILL-IN-CONFIRMATION'"),
    "inert placeholders required");
  assert.ok(cleanup.includes("'CLEANUP-' || v_batch"), "confirmation must match CLEANUP-<batch>");
  const previewIdx = cleanup.indexOf("-- ---- PREVIEW");
  const deleteIdx = cleanup.indexOf("delete from public.jobs where import_batch_id");
  assert.ok(previewIdx !== -1 && deleteIdx !== -1 && previewIdx < deleteIdx,
    "preview precedes deletion");
  assert.ok(cleanup.includes("source not like 'legacy_%'"),
    "refuses non-legacy rows (protects unrelated records)");
  assert.ok(cleanup.includes("t.imported = false"),
    "refuses batches with live (non-imported) activity");
  assert.ok((cleanup.match(/raise exception 'ABORT/g) || []).length >= 6,
    "count/confirmation mismatches abort");
  assert.ok(cleanup.includes("begin;") && cleanup.includes("commit;"), "transactional");
  assert.ok(cleanup.includes("LEGACY_IMPORT_CLEANUP"), "cleanup itself is audited");
  assert.ok(!/delete from public\.audit_logs/.test(cleanup),
    "import audit rows deliberately retained");
});

test("Stage 5: fake sample covers every mandated case with no real data", () => {
  const ids = sample.map(r => r.id);
  assert.ok(ids.includes("LEG-0001"), "normal record");
  assert.ok(sample.some(r => r.status === "follow_up"), "alias-status case");
  assert.ok(ids.includes("LEG-0003-NOREL"), "unresolved relationship case");
  assert.ok(ids.includes("LEG-0004-NOPIN"), "no-PIN case");
  assert.ok(sample.some(r => r.id === "LEG-0005-PIN" && r.closePin), "plaintext-PIN rotate case");
  assert.ok(sample.some(r => (r.attachments || []).some(a => a && a.objectPath)), "stable evidence case");
  assert.ok(sample.some(r => (r.attachments || []).some(a => typeof a === "string" && a.startsWith("data:"))),
    "embedded dataURL failure case");
  assert.ok(sample.some(r => r.deleteRequest), "pseudo-job exclusion case");
  assert.equal(sample.filter(r => r.id === "LEG-SHARED-ID").length, 2, "cross-source shared legacy_id pair");
  assert.equal(new Set(sample.filter(r => r.id === "LEG-SHARED-ID").map(r => r.source)).size, 2,
    "shared pair uses two sources");
  assert.equal(sample.filter(r => r.id === "LEG-0001").length, 2, "repeated record for idempotency");
  const text = JSON.stringify(sample);
  assert.ok(!/@|09\d-\d{3}-\d{4}|08\d-\d{3}-\d{4}/.test(text), "no emails or Thai phone patterns");
  assert.ok(/FAKE|fake|ปลอม/.test(text), "sample explicitly marked fake");
});

test("Stage 5: forward fix 202607110002 uses typed array_append for all five notes", () => {
  const fixPath = path.join(root, "supabase/migrations/202607110002_import_notes_array_fix.sql");
  assert.ok(fs.existsSync(fixPath), "forward migration exists");
  const fix = fs.readFileSync(fixPath, "utf8");
  const fixCode = fix.split("\n").filter(l => !/^\s*--/.test(l)).join("\n");
  for (const note of ["completed_at_defaulted_to_updated_at", "unresolved_reporter",
                      "unresolved_assignee", "unresolved_assigned_by", "unresolved_room"]) {
    assert.ok(fixCode.includes(`v_notes := array_append(v_notes, '${note}'::text);`),
      `${note} uses explicitly typed array_append`);
  }
  // The unsafe text-array pattern must not remain in the EFFECTIVE body
  // (202607110002 is the last definition of import_legacy_job).
  assert.ok(!/v_notes := v_notes \|\|/.test(fixCode),
    "no unsafe v_notes || '...' assignment remains in the effective body");
  // The valid jsonb concatenation is unchanged.
  assert.ok(fixCode.includes("v_stable_refs := v_stable_refs || jsonb_build_array(v_item);"),
    "jsonb concatenation untouched");
  // Public signature and security boundary unchanged.
  assert.ok(fixCode.includes("create or replace function public.import_legacy_job(")
    && fixCode.includes("p_import_batch_id uuid,")
    && fixCode.includes("p_dry_run boolean default true")
    && fixCode.includes("returns jsonb")
    && fixCode.includes("security definer")
    && fixCode.includes("set search_path = public")
    && fixCode.includes("coalesce(auth.role(), '') = 'service_role'"),
    "signature, SECURITY DEFINER, search_path and authorization unchanged");
  assert.ok(!/grant |revoke /i.test(fixCode), "grants preserved via CREATE OR REPLACE (no ACL change)");
  // Applied 202607110001 must not have been rewritten (defect still in the
  // historical file, superseded at runtime).
  assert.ok(migration.includes("v_notes := v_notes || 'completed_at_defaulted_to_updated_at'"),
    "202607110001 was not edited");
});

test("Stage 5: smoke test wraps writes in BEGIN/ROLLBACK and uses no credential", () => {
  assert.ok(/^begin;$/m.test(smoke) && /^rollback;$/m.test(smoke), "write section rolled back");
  assert.ok(smoke.includes("set_config('request.jwt.claims'"),
    "service_role simulated via transaction-local claims, not a credential");
  assert.ok(!/eyJ[A-Za-z0-9_-]{20,}/.test(smoke + cleanup + driver + migration), "no embedded JWT anywhere");
});
