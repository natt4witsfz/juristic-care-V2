"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..");
const profilesJs = fs.readFileSync(path.join(root, "profiles.js"), "utf8");
const appJs = fs.readFileSync(path.join(root, "app.js"), "utf8");
const configJs = fs.readFileSync(path.join(root, "config.js"), "utf8");
const buildScript = fs.readFileSync(path.join(root, "scripts/build-sites-static.mjs"), "utf8");
const migration = fs.readFileSync(
  path.join(root, "supabase/migrations/202607120001_profile_onboarding_stage.sql"), "utf8");
const supabaseClient = fs.readFileSync(path.join(root, "supabase-client.js"), "utf8");

test("post-login onboarding state machine is represented in the profile gate", () => {
  [
    "AUTHENTICATED_NO_PROFILE",
    "PROFILE_SELECTED_PIN_REQUIRED",
    "PROFILE_PIN_VERIFIED",
    "INTERFACE_SELECTION_REQUIRED",
    "APPLICATION_READY"
  ].forEach(state => assert.ok(profilesJs.includes(state), `${state} present`));
  assert.ok(profilesJs.includes("window.__jcShowAppOriginal = showApp"), "wraps showApp instead of duplicating app shell");
  assert.ok(profilesJs.includes("showProfileGate(user)"), "successful login enters profile gate");
});

test("owner profile migration and selection rules are enforced in fallback and SQL", () => {
  assert.ok(profilesJs.includes('profileType: "OWNER"'), "fallback creates Owner profile");
  assert.ok(migration.includes("profile_type = 'OWNER'"), "migration handles Owner profile");
  assert.ok(migration.includes("profile_owner_conflicts"), "duplicate owners are reported");
  assert.ok(migration.includes("idx_room_profiles_one_active_owner"), "unique owner index is attempted when safe");
  assert.ok(migration.includes("PROFILE_TYPE_NOT_ALLOWED"), "RPC blocks creating Owner through optional profile creation");
  assert.ok(profilesJs.includes('data-create-profile="TENANT"'), "Tenant creation UI exists");
  assert.ok(profilesJs.includes('data-create-profile="RESIDENT"'), "Resident creation UI exists");
  assert.ok(profilesJs.includes('profile.status === "ACTIVE"'), "inactive profiles are not selectable");
  assert.ok(migration.includes("account_id = v_account and status = 'ACTIVE'"), "SQL validates profile ownership and active status");
});

test("profile PIN challenge is six-digit, hashed, expiring, attempt-limited and single-use", () => {
  assert.ok(profilesJs.includes("PIN_LENGTH = 6"), "six digit PIN length");
  assert.ok(profilesJs.includes("crypto.getRandomValues"), "browser fallback uses crypto RNG");
  assert.ok(!profilesJs.includes("Math.random"), "no Math.random in fallback PIN generation");
  assert.ok(profilesJs.includes("pinHash"), "fallback stores hash, not raw PIN");
  assert.ok(profilesJs.includes("PIN_TTL_MS = 5 * 60 * 1000"), "five minute expiry");
  assert.ok(profilesJs.includes("PIN_MAX_ATTEMPTS = 5"), "five attempt limit");
  assert.ok(profilesJs.includes("usedAt"), "used PIN tracked");
  assert.ok(profilesJs.includes("invalidatedAt"), "old/failed challenges invalidated");
  assert.ok(migration.includes("profile_pin_challenges"), "backend challenge table exists");
  assert.ok(migration.includes("extensions.gen_random_bytes"), "backend uses pgcrypto randomness");
  assert.ok(migration.includes("extensions.crypt"), "backend stores PIN hash");
  assert.ok(migration.includes("now() + interval '5 minutes'"), "backend expiry exists");
  assert.ok(migration.includes("attempt_count + 1"), "backend increments attempts");
  assert.ok(migration.includes("used_at = now()"), "backend marks PIN used");
  assert.ok(migration.includes("session_id = p_session_id"), "backend binds challenge to session");
});

test("interface selection saves and restores FULL or COMPACT mode", () => {
  assert.ok(appJs.includes('session.interfaceMode = currentInterfaceMode === "compact" ? "COMPACT" : "FULL"'),
    "session stores FULL/COMPACT");
  assert.ok(appJs.includes("openInterfacePicker(force = false)"), "picker supports forced settings change");
  assert.ok(appJs.includes("localStorage.getItem(compactModeStorageKey())"), "previous interface preference is restored");
  assert.ok(appJs.includes("#changeInterfaceModeBtn"), "settings/account menu can reopen picker");
  assert.ok(migration.includes("profile_preferences"), "backend preference table exists");
  assert.ok(migration.includes("save_interface_preference"), "backend save preference RPC exists");
  assert.ok(supabaseClient.includes("saveInterfacePreference"), "frontend adapter exposes preference RPC");
});

test("development PIN display is disabled by default and enabled only for preproduction build", () => {
  assert.ok(configJs.includes("DEV_SHOW_PROFILE_PIN: false"), "default config disables visible PIN");
  assert.ok(buildScript.includes('environment === "preproduction"'), "build has preproduction branch");
  assert.ok(buildScript.includes("DEV_SHOW_PROFILE_PIN: true"), "preproduction build explicitly enables fake-data PIN display");
});

test("Supabase adapter exposes profile onboarding RPC calls", () => {
  [
    "listAccountProfiles",
    "createAccountProfile",
    "selectAccountProfile",
    "issueProfilePinChallenge",
    "verifyProfilePinChallenge",
    "saveInterfacePreference"
  ].forEach(name => assert.ok(supabaseClient.includes(name), `${name} exported`));
});
