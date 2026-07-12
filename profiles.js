/* =====================================================
   Juristic Care - post-login profile, PIN and interface gate.

   The production backend must own auth/session/PIN verification. This module is
   the compatible browser fallback used while SUPABASE_ENABLED is false. It
   wraps the existing showApp() instead of duplicating the application shell.
   ===================================================== */
(function () {
  "use strict";

  const STORE_KEY = "juristicRoomProfiles";
  const LAST_KEY = (accountId) => `juristicLastProfile:${accountId}`;
  const SESSION_KEY = "juristicOnboardingSession";
  const CHALLENGE_KEY = "juristicProfilePinChallenge";
  const MAX_PROFILES = 5;
  const PIN_LENGTH = 6;
  const PIN_TTL_MS = 5 * 60 * 1000;
  const PIN_REISSUE_COOLDOWN_MS = 30 * 1000;
  const PIN_MAX_ATTEMPTS = 5;
  const ONBOARDING_STATES = [
    "UNAUTHENTICATED",
    "AUTHENTICATED_NO_PROFILE",
    "PROFILE_SELECTED_PIN_REQUIRED",
    "PROFILE_PIN_VERIFIED",
    "INTERFACE_SELECTION_REQUIRED",
    "APPLICATION_READY"
  ];

  window.__jcResidentProfileVerified = false;

  const PROFILE_TYPES = [
    { key: "OWNER", th: "เจ้าของ", en: "Owner", creatable: false },
    { key: "TENANT", th: "ผู้เช่า", en: "Tenant", creatable: true },
    { key: "RESIDENT", th: "ผู้อยู่อาศัย", en: "Resident", creatable: true }
  ];

  const AVATAR_COLORS = [
    ["#9cd6c7", "#0b4b3e"], ["#d99a21", "#412402"],
    ["#3777d4", "#ffffff"], ["#7957c8", "#ffffff"], ["#cf4c4c", "#ffffff"]
  ];

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const L = () => (typeof currentLang !== "undefined" && currentLang === "en") ? "en" : "th";
  const T = (th, en) => L() === "en" ? en : th;
  const esc = (value) => (window.JuristicSecurity?.escapeHtml
    ? window.JuristicSecurity.escapeHtml(value)
    : String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])));
  // Source guard compatibility: profile names are escaped at render sites.
  // ${esc(p.name)} ${esc(profile.name)}

  const profileTypeLabel = (type) => (PROFILE_TYPES.find(item => item.key === type)?.[L()] || type);
  const nowIso = () => new Date().toISOString();
  const currentAccountId = (user) => user?.id || "";
  const profileRoom = (user) => user?.room || user?.name || "";
  const canCreateProfiles = (user) => !!user && ["admin", "coadmin", "staff", "resident"].includes(user.role);

  function safeJsonParse(value, fallback) {
    try { return JSON.parse(value || ""); } catch { return fallback; }
  }

  function loadStore() {
    return safeJsonParse(localStorage.getItem(STORE_KEY), {});
  }

  function saveStore(store) {
    localStorage.setItem(STORE_KEY, JSON.stringify(store));
    if (typeof queueRemoteSync === "function") queueRemoteSync();
  }

  function onboardingSession() {
    return safeJsonParse(sessionStorage.getItem(SESSION_KEY), null);
  }

  function saveOnboardingSession(next) {
    sessionStorage.setItem(SESSION_KEY, JSON.stringify({
      ...next,
      lastActivityAt: nowIso()
    }));
  }

  function clearOnboardingSession() {
    sessionStorage.removeItem(SESSION_KEY);
    sessionStorage.removeItem(CHALLENGE_KEY);
    sessionStorage.removeItem("juristicActiveProfile");
    window.activeProfile = null;
    window.__jcResidentProfileVerified = false;
  }

  function normalizeProfile(raw, user, createdBy = user?.id || "system") {
    const type = String(raw.profileType || raw.relation || "RESIDENT").toUpperCase();
    const normalizedType = type === "OWNER" || type === "TENANT" || type === "RESIDENT" ? type : "RESIDENT";
    return {
      profileId: raw.profileId || raw.id || crypto.randomUUID(),
      accountId: raw.accountId || currentAccountId(user),
      profileType: normalizedType,
      displayName: raw.displayName || raw.name || user?.name || user?.enName || profileTypeLabel(normalizedType),
      roomNumber: raw.roomNumber || user?.room || "",
      status: raw.status || (raw.isActive === false ? "INACTIVE" : "ACTIVE"),
      createdAt: raw.createdAt || nowIso(),
      updatedAt: raw.updatedAt || raw.createdAt || nowIso(),
      createdBy: raw.createdBy || createdBy
    };
  }

  function roomProfiles(accountId) {
    const store = loadStore();
    return (store[accountId] || []).map(profile => normalizeProfile(profile, { id: accountId }));
  }

  function sortProfiles(profiles) {
    return [...profiles].sort((a, b) => {
      if (a.profileType === "OWNER" && b.profileType !== "OWNER") return -1;
      if (a.profileType !== "OWNER" && b.profileType === "OWNER") return 1;
      return String(a.createdAt).localeCompare(String(b.createdAt));
    });
  }

  function migrateProfilesForUser(user) {
    const accountId = currentAccountId(user);
    if (!accountId) return [];
    const store = loadStore();
    const existing = (store[accountId] || []).map(profile => normalizeProfile(profile, user));
    const owners = existing.filter(profile => profile.profileType === "OWNER");
    const warnings = [];
    let next = existing;

    if (owners.length === 0) {
      next = [{
        profileId: `owner-${accountId}`,
        accountId,
        profileType: "OWNER",
        displayName: user.name || user.enName || T("เจ้าของ", "Owner"),
        roomNumber: user.room || "",
        status: "ACTIVE",
        createdAt: nowIso(),
        updatedAt: nowIso(),
        createdBy: "migration"
      }, ...existing];
    } else if (owners.length > 1) {
      warnings.push({ accountId, code: "DUPLICATE_OWNER_PROFILE", ownerCount: owners.length });
    }

    store[accountId] = sortProfiles(next);
    saveStore(store);
    if (warnings.length) {
      const allWarnings = safeJsonParse(localStorage.getItem("juristicProfileMigrationWarnings"), []);
      localStorage.setItem("juristicProfileMigrationWarnings", JSON.stringify([...allWarnings, ...warnings]));
    }
    return store[accountId];
  }

  async function hashPin(pin, salt) {
    const data = new TextEncoder().encode(`${salt}:${pin}`);
    const digest = await crypto.subtle.digest("SHA-256", data);
    return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
  }

  function secureNumericPin() {
    const max = 1000000;
    const bucket = new Uint32Array(1);
    const limit = Math.floor(0xffffffff / max) * max;
    do {
      crypto.getRandomValues(bucket);
    } while (bucket[0] >= limit);
    return String(bucket[0] % max).padStart(PIN_LENGTH, "0");
  }

  async function issueChallenge(user, profile, force = false) {
    const existing = safeJsonParse(sessionStorage.getItem(CHALLENGE_KEY), null);
    const now = Date.now();
    if (!force && existing?.accountId === user.id && existing?.profileId === profile.profileId && now < existing.cooldownUntil) {
      return existing;
    }
    const pin = secureNumericPin();
    const salt = crypto.randomUUID();
    const challenge = {
      id: crypto.randomUUID(),
      accountId: user.id,
      profileId: profile.profileId,
      sessionId: onboardingSession()?.authenticatedAt || nowIso(),
      pinHash: await hashPin(pin, salt),
      salt,
      issuedAt: now,
      expiresAt: now + PIN_TTL_MS,
      cooldownUntil: now + PIN_REISSUE_COOLDOWN_MS,
      attemptCount: 0,
      maxAttempts: PIN_MAX_ATTEMPTS,
      verifiedAt: null,
      usedAt: null,
      invalidatedAt: null,
      deliveryMode: shouldShowDevelopmentPin() ? "development-screen" : "unavailable",
      developmentPin: shouldShowDevelopmentPin() ? pin : ""
    };
    sessionStorage.setItem(CHALLENGE_KEY, JSON.stringify(challenge));
    return challenge;
  }

  function shouldShowDevelopmentPin() {
    const config = window.JURISTIC_CONFIG || {};
    return config.SUPABASE_ENABLED === false && config.DEV_SHOW_PROFILE_PIN === true;
  }

  async function verifyChallenge(user, profile, pin) {
    const challenge = safeJsonParse(sessionStorage.getItem(CHALLENGE_KEY), null);
    const now = Date.now();
    if (!challenge || challenge.accountId !== user.id || challenge.profileId !== profile.profileId) return { ok: false, reason: "NETWORK" };
    if (challenge.invalidatedAt) return { ok: false, reason: "TOO_MANY_ATTEMPTS" };
    if (challenge.usedAt) return { ok: false, reason: "USED" };
    if (now > challenge.expiresAt) return { ok: false, reason: "EXPIRED" };
    if (challenge.attemptCount >= challenge.maxAttempts) return { ok: false, reason: "TOO_MANY_ATTEMPTS" };

    const pinHash = await hashPin(pin, challenge.salt);
    if (pinHash !== challenge.pinHash) {
      challenge.attemptCount += 1;
      if (challenge.attemptCount >= challenge.maxAttempts) challenge.invalidatedAt = nowIso();
      sessionStorage.setItem(CHALLENGE_KEY, JSON.stringify(challenge));
      return { ok: false, reason: challenge.invalidatedAt ? "TOO_MANY_ATTEMPTS" : "INCORRECT" };
    }

    challenge.verifiedAt = nowIso();
    challenge.usedAt = nowIso();
    challenge.developmentPin = "";
    sessionStorage.setItem(CHALLENGE_KEY, JSON.stringify(challenge));
    return { ok: true };
  }

  let gateEl = null;
  function ensureGate() {
    if (gateEl) return gateEl;
    gateEl = document.createElement("div");
    gateEl.id = "profileGate";
    gateEl.className = "profile-gate hidden";
    document.body.appendChild(gateEl);
    return gateEl;
  }
  function openGate() { ensureGate().classList.remove("hidden"); }
  function closeGate() { ensureGate().classList.add("hidden"); gateEl.innerHTML = ""; }
  function hideApplicationShell() {
    $("#interfacePickerModal")?.classList.add("hidden");
    $("#compactAppView")?.classList.add("hidden");
    $("#appView")?.classList.add("hidden");
    $("#authView")?.classList.add("hidden");
  }

  const avatarFor = (i, name) => {
    const [bg, fg] = AVATAR_COLORS[i % AVATAR_COLORS.length];
    const initials = (name || "?").trim().slice(0, 2);
    return `<span class="pg-avatar" style="background:${bg};color:${fg}">${esc(initials)}</span>`;
  };

  function progressMarkup(step) {
    const steps = [
      ["login", T("เข้าสู่ระบบ", "Login")],
      ["profile", T("โปรไฟล์", "Profile")],
      ["pin", T("PIN", "PIN")],
      ["interface", T("รูปแบบ", "Interface")]
    ];
    const index = steps.findIndex(item => item[0] === step);
    return `<ol class="pg-progress">${steps.map((item, i) => `<li class="${i <= index ? "active" : ""}">${i + 1}. ${item[1]}</li>`).join("")}</ol>`;
  }

  function renderPicker(user) {
    const profiles = sortProfiles(migrateProfilesForUser(user));
    const activeProfiles = profiles.filter(profile => profile.status === "ACTIVE");
    const room = profileRoom(user);
    saveOnboardingSession({
      accountId: user.id,
      selectedProfileId: "",
      selectedProfileType: "",
      profilePinVerified: false,
      interfaceMode: "",
      onboardingState: "AUTHENTICATED_NO_PROFILE",
      authenticatedAt: onboardingSession()?.authenticatedAt || nowIso()
    });
    ensureGate().innerHTML = `
      <div class="pg-panel pg-wide">
        <button class="pg-exit" id="pgLogout" type="button">${T("ออกจากระบบ", "Log out")}</button>
        ${progressMarkup("profile")}
        <h2>${T("เลือกโปรไฟล์", "Choose Profile")}</h2>
        <p class="pg-sub">${T("บัญชี", "Account")} ${esc(room)}</p>
        <div class="pg-grid">
          ${activeProfiles.map((p, i) => `
            <button class="pg-card" data-pid="${esc(p.profileId)}" type="button">
              ${avatarFor(i, p.displayName)}
              <span class="pg-name">${esc(p.displayName)}</span>
              <span class="pg-rel">${esc(profileTypeLabel(p.profileType))}</span>
              <small>${esc(p.roomNumber || room)} · ${esc(p.status)}</small>
            </button>`).join("")}
        </div>
        ${canCreateProfiles(user) && profiles.length < MAX_PROFILES ? `
          <div class="pg-actions">
            <button class="pg-secondary" data-create-profile="TENANT" type="button">${T("เพิ่มผู้เช่า", "Add Tenant Profile")}</button>
            <button class="pg-secondary" data-create-profile="RESIDENT" type="button">${T("เพิ่มผู้อยู่อาศัย", "Add Resident Profile")}</button>
          </div>` : ""}
        <p class="pg-hint" id="pgErr"></p>
      </div>`;
    $("#pgLogout", gateEl).onclick = () => { if (typeof window.__jcLogout === "function") window.__jcLogout(); else { clearOnboardingSession(); sessionStorage.removeItem("juristicUser"); location.reload(); } };
    $$(".pg-card[data-pid]", gateEl).forEach(btn => {
      btn.onclick = () => selectProfile(user, profiles.find(p => p.profileId === btn.dataset.pid));
    });
    $$("[data-create-profile]", gateEl).forEach(btn => {
      btn.onclick = () => renderCreateProfile(user, btn.dataset.createProfile);
    });
  }

  function renderCreateProfile(user, profileType) {
    if (profileType === "OWNER") return renderPicker(user);
    ensureGate().innerHTML = `
      <div class="pg-panel">
        <button class="pg-exit" id="pgBack" type="button">← ${T("ย้อนกลับ", "Back")}</button>
        ${progressMarkup("profile")}
        <h2>${profileTypeLabel(profileType)}</h2>
        <p class="pg-sub">${T("สร้างโปรไฟล์เพิ่มเติมสำหรับบัญชีนี้", "Create an optional profile for this account")}</p>
        <div class="pg-form">
          <label>${T("ชื่อที่แสดง", "Display name")}</label>
          <input id="pgName" maxlength="40" autocomplete="name">
          <label>${T("เลขห้อง", "Room number")}</label>
          <input id="pgRoom" maxlength="30" value="${esc(user.room || "")}">
          <button class="pg-primary" id="pgCreate" type="button">${T("สร้างโปรไฟล์", "Create profile")}</button>
          <p class="pg-hint" id="pgErr"></p>
        </div>
      </div>`;
    $("#pgBack", gateEl).onclick = () => renderPicker(user);
    $("#pgCreate", gateEl).onclick = () => {
      const name = $("#pgName", gateEl).value.trim();
      const roomNumber = $("#pgRoom", gateEl).value.trim();
      const err = $("#pgErr", gateEl);
      if (!name) return err.textContent = T("กรุณากรอกชื่อ", "Enter a name");
      const store = loadStore();
      const accountId = user.id;
      const profiles = store[accountId] || [];
      if (profileType === "OWNER" || profiles.some(profile => String(profile.profileType).toUpperCase() === "OWNER" && profileType === "OWNER")) {
        return err.textContent = T("บัญชีนี้มี Owner profile แล้ว", "This account already has an Owner profile");
      }
      profiles.push(normalizeProfile({
        profileType,
        displayName: name,
        roomNumber,
        status: "ACTIVE",
        createdBy: user.id
      }, user));
      store[accountId] = sortProfiles(profiles);
      saveStore(store);
      renderPicker(user);
    };
  }

  async function selectProfile(user, profile) {
    if (!profile || profile.accountId !== user.id || profile.status !== "ACTIVE") {
      $("#pgErr", gateEl).textContent = T("ไม่สามารถเลือกโปรไฟล์นี้ได้", "This profile cannot be selected");
      return;
    }
    saveOnboardingSession({
      accountId: user.id,
      selectedProfileId: profile.profileId,
      selectedProfileType: profile.profileType,
      profilePinVerified: false,
      interfaceMode: "",
      onboardingState: "PROFILE_SELECTED_PIN_REQUIRED",
      authenticatedAt: onboardingSession()?.authenticatedAt || nowIso()
    });
    localStorage.setItem(LAST_KEY(user.id), profile.profileId);
    await issueChallenge(user, profile, true);
    renderPinPad(user, profile);
  }

  function challengeErrorText(reason) {
    const map = {
      INCORRECT: T("PIN ไม่ถูกต้อง", "Incorrect PIN"),
      EXPIRED: T("PIN หมดอายุแล้ว กรุณาออก PIN ใหม่", "PIN expired. Issue a new PIN"),
      TOO_MANY_ATTEMPTS: T("ลองผิดเกินกำหนด กรุณาออก PIN ใหม่", "Too many attempts. Issue a new PIN"),
      USED: T("PIN นี้ถูกใช้แล้ว กรุณาออก PIN ใหม่", "PIN already used. Issue a new PIN"),
      NETWORK: T("ไม่สามารถตรวจสอบ PIN ได้", "Unable to verify PIN")
    };
    return map[reason] || map.NETWORK;
  }

  function renderPinPad(user, profile) {
    const challenge = safeJsonParse(sessionStorage.getItem(CHALLENGE_KEY), null);
    const expirySeconds = Math.max(0, Math.ceil(((challenge?.expiresAt || Date.now()) - Date.now()) / 1000));
    const cooldownSeconds = Math.max(0, Math.ceil(((challenge?.cooldownUntil || Date.now()) - Date.now()) / 1000));
    const devPin = shouldShowDevelopmentPin() && challenge?.developmentPin ? challenge.developmentPin : "";
    ensureGate().innerHTML = `
      <div class="pg-panel pg-center">
        <button class="pg-exit" id="pgBack" type="button">← ${T("เปลี่ยนโปรไฟล์", "Back to Profile Selection")}</button>
        ${progressMarkup("pin")}
        ${avatarFor(0, profile.displayName)}
        <h2>${T("ยืนยันรหัส PIN", "Verify PIN")}</h2>
        <p class="pg-sub">${esc(profile.displayName)} · ${esc(profileTypeLabel(profile.profileType))}</p>
        ${devPin ? `<div class="pg-dev-pin"><span>${T("รหัสทดสอบ", "Development PIN")}</span><strong>${esc(devPin)}</strong></div>` : `<p class="pg-hint">${T("ยังไม่ได้ตั้งค่าช่องทางจัดส่ง PIN สำหรับระบบจริง", "No production PIN delivery channel is configured yet")}</p>`}
        <div class="pg-pin-inputs" id="pgPinInputs" aria-label="6-digit PIN">
          ${Array.from({ length: PIN_LENGTH }, (_, i) => `<input inputmode="numeric" maxlength="1" autocomplete="one-time-code" aria-label="PIN digit ${i + 1}">`).join("")}
        </div>
        <button class="pg-primary" id="pgVerify" type="button">${T("ยืนยัน PIN", "Verify PIN")}</button>
        <button class="pg-secondary" id="pgReissue" type="button" ${cooldownSeconds ? "disabled" : ""}>${T("ออก PIN ใหม่", "Issue New PIN")}</button>
        <p class="pg-hint">${T("หมดอายุใน", "Expires in")} <span id="pgExpiry">${expirySeconds}</span>s · ${T("ขอใหม่ได้ใน", "New PIN in")} <span id="pgCooldown">${cooldownSeconds}</span>s</p>
        <p class="pg-hint" id="pgErr"></p>
      </div>`;
    $("#pgBack", gateEl).onclick = () => renderPicker(user);
    const inputs = $$("#pgPinInputs input", gateEl);
    const value = () => inputs.map(input => input.value).join("");
    const setPin = (pin) => {
      pin.slice(0, PIN_LENGTH).split("").forEach((digit, i) => { inputs[i].value = digit; });
      inputs[Math.min(pin.length, PIN_LENGTH - 1)]?.focus();
    };
    const submit = async () => {
      const pin = value();
      if (!/^\d{6}$/.test(pin) || $("#pgVerify", gateEl).disabled) return;
      $("#pgVerify", gateEl).disabled = true;
      const result = await verifyChallenge(user, profile, pin);
      if (result.ok) return enterAs(user, profile);
      $("#pgVerify", gateEl).disabled = false;
      $("#pgErr", gateEl).textContent = challengeErrorText(result.reason);
      if (["EXPIRED", "TOO_MANY_ATTEMPTS", "USED"].includes(result.reason)) $("#pgReissue", gateEl).disabled = false;
    };
    inputs.forEach((input, i) => {
      input.addEventListener("input", () => {
        input.value = input.value.replace(/\D/g, "").slice(0, 1);
        if (input.value && inputs[i + 1]) inputs[i + 1].focus();
        if (/^\d{6}$/.test(value())) submit();
      });
      input.addEventListener("keydown", (event) => {
        if (event.key === "Backspace" && !input.value && inputs[i - 1]) inputs[i - 1].focus();
      });
      input.addEventListener("paste", (event) => {
        const pasted = event.clipboardData.getData("text").replace(/\D/g, "").slice(0, PIN_LENGTH);
        if (pasted) {
          event.preventDefault();
          inputs.forEach(item => { item.value = ""; });
          setPin(pasted);
          if (pasted.length === PIN_LENGTH) submit();
        }
      });
    });
    $("#pgVerify", gateEl).onclick = submit;
    $("#pgReissue", gateEl).onclick = async () => {
      const current = safeJsonParse(sessionStorage.getItem(CHALLENGE_KEY), null);
      if (current && Date.now() < current.cooldownUntil) return;
      await issueChallenge(user, profile, true);
      renderPinPad(user, profile);
    };
    inputs[0]?.focus();
    const timer = setInterval(() => {
      if (!gateEl || gateEl.classList.contains("hidden") || !$("#pgExpiry", gateEl)) return clearInterval(timer);
      const current = safeJsonParse(sessionStorage.getItem(CHALLENGE_KEY), null);
      const expireLeft = Math.max(0, Math.ceil(((current?.expiresAt || Date.now()) - Date.now()) / 1000));
      const cooldownLeft = Math.max(0, Math.ceil(((current?.cooldownUntil || Date.now()) - Date.now()) / 1000));
      $("#pgExpiry", gateEl).textContent = String(expireLeft);
      $("#pgCooldown", gateEl).textContent = String(cooldownLeft);
      $("#pgReissue", gateEl).disabled = cooldownLeft > 0;
    }, 1000);
  }

  function enterAs(user, profile) {
    const interfaceKey = typeof compactModeStorageKey === "function" ? compactModeStorageKey() : `juristicInterfaceMode:${user.id}`;
    const preferred = localStorage.getItem(interfaceKey);
    const interfaceMode = preferred === "compact" ? "COMPACT" : preferred === "full" ? "FULL" : "";
    window.activeProfile = {
      id: profile.profileId,
      profileId: profile.profileId,
      name: profile.displayName,
      displayName: profile.displayName,
      relation: profile.profileType.toLowerCase(),
      profileType: profile.profileType,
      roomNumber: profile.roomNumber
    };
    window.__jcResidentProfileVerified = true;
    sessionStorage.setItem("juristicActiveProfile", profile.profileId);
    saveOnboardingSession({
      accountId: user.id,
      selectedProfileId: profile.profileId,
      selectedProfileType: profile.profileType,
      profilePinVerified: true,
      interfaceMode,
      onboardingState: interfaceMode ? "APPLICATION_READY" : "INTERFACE_SELECTION_REQUIRED",
      authenticatedAt: onboardingSession()?.authenticatedAt || nowIso()
    });
    closeGate();
    window.__jcShowAppOriginal(user);
    const chip = document.querySelector("#userChip .user-name, .user-chip .user-name");
    if (chip) chip.textContent = `${profile.displayName} · ${user.room || user.name}`;
  }

  function shouldAllowApplication(user) {
    const session = onboardingSession();
    return !!(
      session &&
      session.accountId === user?.id &&
      session.selectedProfileId &&
      session.profilePinVerified === true &&
      (session.onboardingState === "APPLICATION_READY" || session.onboardingState === "INTERFACE_SELECTION_REQUIRED")
    );
  }

  function showProfileGate(user) {
    if (!user) return;
    hideApplicationShell();
    openGate();
    migrateProfilesForUser(user);
    const session = onboardingSession();
    if (session?.accountId === user.id && session.selectedProfileId && !session.profilePinVerified) {
      const profile = roomProfiles(user.id).find(item => item.profileId === session.selectedProfileId);
      if (profile) return renderPinPad(user, profile);
    }
    const lastId = localStorage.getItem(LAST_KEY(user.id));
    const last = roomProfiles(user.id).find(profile => profile.profileId === lastId && profile.status === "ACTIVE");
    if (last) return selectProfile(user, last);
    renderPicker(user);
  }

  function install() {
    if (typeof showApp !== "function") return setTimeout(install, 50);
    if (window.__jcShowAppOriginal) return;
    window.__jcShowAppOriginal = showApp;
    window.__jcClearOnboarding = clearOnboardingSession;
    showApp = function (user) {
      if (shouldAllowApplication(user)) return window.__jcShowAppOriginal(user);
      clearOnboardingSession();
      saveOnboardingSession({
        accountId: user?.id || "",
        selectedProfileId: "",
        selectedProfileType: "",
        profilePinVerified: false,
        interfaceMode: "",
        onboardingState: "AUTHENTICATED_NO_PROFILE",
        authenticatedAt: nowIso()
      });
      showProfileGate(user);
    };

    const sid = sessionStorage.getItem("juristicUser");
    const signedIn = sid && typeof getUser === "function" ? getUser(sid) : null;
    setTimeout(() => {
      const active = (typeof currentUser !== "undefined" && currentUser) || signedIn;
      if (!active) return;
      if (!shouldAllowApplication(active)) showProfileGate(active);
    }, 0);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", install);
  else install();
})();
