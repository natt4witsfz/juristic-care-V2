"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { escapeHtml, generateTempPassword, isDemoAccount, DEMO_ACCOUNT_CODES } =
  require("../js/security.js");

test("escapeHtml neutralizes all HTML metacharacters", () => {
  assert.equal(escapeHtml("<script>"), "&lt;script&gt;");
  assert.equal(escapeHtml('a & b "c" \'d\''), "a &amp; b &quot;c&quot; &#39;d&#39;");
  assert.equal(escapeHtml(">"), "&gt;");
});

test("escapeHtml renders a malicious job/profile name as inert text", () => {
  const payload = '<img src=x onerror="alert(1)">';
  const out = escapeHtml(payload);
  assert.ok(!out.includes("<"), "no raw < remains");
  assert.ok(!out.includes(">"), "no raw > remains");
  assert.ok(out.includes("&lt;img"), "tag is escaped, not executable");
});

test("escapeHtml handles null/undefined/numbers safely", () => {
  assert.equal(escapeHtml(null), "");
  assert.equal(escapeHtml(undefined), "");
  assert.equal(escapeHtml(42), "42");
});

test("generateTempPassword is never the legacy default and meets policy", () => {
  for (let i = 0; i < 200; i++) {
    const pw = generateTempPassword(10);
    assert.notEqual(pw, "1234");
    assert.equal(pw.length, 10);
    assert.ok(/[A-Za-z]/.test(pw), "contains a letter");
    assert.ok(/[0-9]/.test(pw), "contains a digit");
    assert.ok(!/[0O1lI]/.test(pw), "excludes ambiguous characters");
  }
});

test("generateTempPassword is effectively unique across calls", () => {
  const set = new Set();
  for (let i = 0; i < 500; i++) set.add(generateTempPassword(10));
  assert.ok(set.size > 490, `expected high uniqueness, got ${set.size}/500`);
});

test("generateTempPassword enforces a minimum length floor", () => {
  assert.ok(generateTempPassword(3).length >= 8);
});

test("isDemoAccount recognizes seeded demo codes and rejects others", () => {
  assert.equal(isDemoAccount("ADMIN"), true);
  assert.equal(isDemoAccount("staff-01"), true); // case-insensitive
  assert.equal(isDemoAccount("A-0201"), true);
  assert.equal(isDemoAccount("A-1509"), false);
  assert.equal(isDemoAccount(""), false);
  assert.equal(isDemoAccount(null), false);
  assert.ok(DEMO_ACCOUNT_CODES.includes("ADMIN"));
});
