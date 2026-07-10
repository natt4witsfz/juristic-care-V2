/* =====================================================
   Juristic Care — Room Profiles (Netflix-style) + PIN
   โมดูลแยกไฟล์ ไม่แก้ app.js เดิม: ครอบ showApp() ไว้
   - 1 ห้อง = 1 บัญชี login / หลายโปรไฟล์ (สูงสุด 5)
   - PIN 4 หลักต่อโปรไฟล์ เก็บเป็น SHA-256 hash + salt
   - จำโปรไฟล์ล่าสุด: ครั้งถัดไปข้ามไปถาม PIN เลย
   - เจ้าหน้าที่ (admin/staff) ข้ามขั้นนี้ทั้งหมด
   หมายเหตุ: บน localStorage นี่คือการป้องกันระดับ pilot
   เมื่อย้าย Supabase ให้ตรวจ PIN ผ่าน RPC ฝั่งเซิร์ฟเวอร์
   (ดู supabase-schema.sql) โดยแก้แค่ฟังก์ชัน verifyPin/setPin
   ===================================================== */
(function () {
  const STORE_KEY = "juristicRoomProfiles";
  const LAST_KEY = (roomId) => `juristicLastProfile:${roomId}`;
  const MAX_PROFILES = 5;
  window.__jcResidentProfileVerified = false;

  const RELATIONS = [
    { key: "owner", th: "เจ้าของห้อง", en: "Owner" },
    { key: "coowner", th: "เจ้าของร่วม", en: "Co-owner" },
    { key: "tenant", th: "ผู้เช่า", en: "Tenant" },
    { key: "resident", th: "ผู้อยู่อาศัย", en: "Resident" }
  ];
  const AVATAR_COLORS = [
    ["#9cd6c7", "#0b4b3e"], ["#d99a21", "#412402"],
    ["#3777d4", "#ffffff"], ["#7957c8", "#ffffff"], ["#cf4c4c", "#ffffff"]
  ];

  const L = () => (typeof currentLang !== "undefined" && currentLang === "en") ? "en" : "th";
  const T = (th, en) => L() === "en" ? en : th;
  const esc = (value) => (window.JuristicSecurity?.escapeHtml
    ? window.JuristicSecurity.escapeHtml(value)
    : String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])));
  const relLabel = (key) => {
    const r = RELATIONS.find(x => x.key === key);
    return r ? r[L()] : key;
  };

  function loadStore() {
    try { return JSON.parse(localStorage.getItem(STORE_KEY) || "{}"); } catch { return {}; }
  }
  function saveStore(store) {
    localStorage.setItem(STORE_KEY, JSON.stringify(store));
    if (typeof queueRemoteSync === "function") queueRemoteSync();
  }
  function roomProfiles(roomId) { return loadStore()[roomId] || []; }

  async function hashPin(pin, salt) {
    const data = new TextEncoder().encode(`${salt}:${pin}`);
    const digest = await crypto.subtle.digest("SHA-256", data);
    return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
  }
  async function setPin(profile, pin) {
    profile.salt = crypto.randomUUID();
    profile.pinHash = await hashPin(pin, profile.salt);
  }
  async function verifyPin(profile, pin) {
    return profile.pinHash === await hashPin(pin, profile.salt);
  }

  /* ---------- UI ---------- */
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

  const avatarFor = (i, name) => {
    const [bg, fg] = AVATAR_COLORS[i % AVATAR_COLORS.length];
    const initials = (name || "?").trim().slice(0, 2);
    return `<span class="pg-avatar" style="background:${bg};color:${fg}">${esc(initials)}</span>`;
  };

  function renderPicker(user) {
    const profiles = roomProfiles(user.id);
    const room = user.room || user.name;
    ensureGate().innerHTML = `
      <div class="pg-panel">
        <button class="pg-exit" id="pgLogout" type="button">${T("ออกจากระบบ", "Log out")}</button>
        <h2>${T("ใครกำลังใช้งาน", "Who's using this")}</h2>
        <p class="pg-sub">${T("ห้อง", "Room")} ${room}</p>
        <div class="pg-grid">
          ${profiles.map((p, i) => `
            <button class="pg-card" data-pid="${esc(p.id)}" type="button">
              ${avatarFor(i, p.name)}
              <span class="pg-name">${esc(p.name)}</span>
              <span class="pg-rel">${esc(relLabel(p.relation))}</span>
            </button>`).join("")}
          ${profiles.length < MAX_PROFILES ? `
            <button class="pg-card pg-add" id="pgAdd" type="button">
              <span class="pg-avatar pg-avatar-add">+</span>
              <span class="pg-name">${T("เพิ่มสมาชิก", "Add member")}</span>
              <span class="pg-rel">${T("สูงสุด", "Max")} ${MAX_PROFILES} ${T("คน", "people")}</span>
            </button>` : ""}
        </div>
      </div>`;
    gateEl.querySelector("#pgLogout").onclick = () => { sessionStorage.removeItem("juristicUser"); location.reload(); };
    gateEl.querySelectorAll(".pg-card[data-pid]").forEach(btn => {
      btn.onclick = () => renderPinPad(user, profiles.find(p => p.id === btn.dataset.pid));
    });
    const add = gateEl.querySelector("#pgAdd");
    if (add) add.onclick = () => renderCreateProfile(user);
  }

  function renderCreateProfile(user, first = false) {
    ensureGate().innerHTML = `
      <div class="pg-panel">
        ${first ? "" : `<button class="pg-exit" id="pgBack" type="button">← ${T("ย้อนกลับ", "Back")}</button>`}
        <h2>${first ? T("สร้างโปรไฟล์แรกของห้อง", "Create your room's first profile") : T("เพิ่มสมาชิกใหม่", "Add a member")}</h2>
        <p class="pg-sub">${T("ห้อง", "Room")} ${user.room || user.name}</p>
        <div class="pg-form">
          <label>${T("ชื่อเรียก", "Display name")}</label>
          <input id="pgName" maxlength="20" placeholder="${T("เช่น สมชาย", "e.g. Somchai")}">
          <label>${T("ความสัมพันธ์กับห้อง", "Relation to the room")}</label>
          <select id="pgRel">${RELATIONS.map(r => `<option value="${r.key}">${r[L()]}</option>`).join("")}</select>
          <label>${T("ตั้ง PIN 4 หลัก", "Set a 4-digit PIN")}</label>
          <input id="pgPin" inputmode="numeric" maxlength="4" placeholder="••••" type="password">
          <button class="pg-primary" id="pgCreate" type="button">${T("สร้างโปรไฟล์", "Create profile")}</button>
          <p class="pg-hint" id="pgErr"></p>
        </div>
      </div>`;
    const back = gateEl.querySelector("#pgBack");
    if (back) back.onclick = () => renderPicker(user);
    gateEl.querySelector("#pgCreate").onclick = async () => {
      const name = gateEl.querySelector("#pgName").value.trim();
      const relation = gateEl.querySelector("#pgRel").value;
      const pin = gateEl.querySelector("#pgPin").value.trim();
      const err = gateEl.querySelector("#pgErr");
      if (!name) return err.textContent = T("กรุณากรอกชื่อ", "Enter a name");
      if (!/^\d{4}$/.test(pin)) return err.textContent = T("PIN ต้องเป็นตัวเลข 4 หลัก", "PIN must be 4 digits");
      const profile = { id: crypto.randomUUID(), name, relation, createdAt: new Date().toISOString() };
      await setPin(profile, pin);
      const store = loadStore();
      store[user.id] = [...(store[user.id] || []), profile];
      saveStore(store);
      enterAs(user, profile);
    };
  }

  function renderPinPad(user, profile, allowSwitch = true) {
    let entered = "";
    const profiles = roomProfiles(user.id);
    const idx = Math.max(0, profiles.findIndex(p => p.id === profile.id));
    ensureGate().innerHTML = `
      <div class="pg-panel pg-center">
        ${allowSwitch ? `<button class="pg-exit" id="pgBack" type="button">← ${T("เปลี่ยนโปรไฟล์", "Switch profile")}</button>` : ""}
        ${avatarFor(idx, profile.name)}
        <h2>${T("สวัสดี", "Hi")} ${esc(profile.name)}</h2>
        <p class="pg-sub">${T("กรอก PIN 4 หลักของคุณ", "Enter your 4-digit PIN")}</p>
        <div class="pg-dots" id="pgDots"></div>
        <div class="pg-pad" id="pgPad"></div>
        <p class="pg-hint" id="pgErr"></p>
      </div>`;
    const back = gateEl.querySelector("#pgBack");
    if (back) back.onclick = () => renderPicker(user);
    const dots = gateEl.querySelector("#pgDots");
    const drawDots = () => dots.innerHTML = [0, 1, 2, 3].map(i =>
      `<span class="pg-dot ${i < entered.length ? "on" : ""} ${i === entered.length ? "cur" : ""}"></span>`).join("");
    drawDots();
    const pad = gateEl.querySelector("#pgPad");
    const keys = ["1","2","3","4","5","6","7","8","9","",  "0","⌫"];
    pad.innerHTML = keys.map(k => k === "" ? `<span></span>` :
      `<button type="button" class="pg-key" data-k="${k}">${k}</button>`).join("");
    pad.querySelectorAll(".pg-key").forEach(btn => btn.onclick = async () => {
      const k = btn.dataset.k;
      if (k === "⌫") entered = entered.slice(0, -1);
      else if (entered.length < 4) entered += k;
      drawDots();
      if (entered.length === 4) {
        if (await verifyPin(profile, entered)) {
          localStorage.setItem(LAST_KEY(user.id), profile.id);
          enterAs(user, profile);
        } else {
          entered = "";
          drawDots();
          gateEl.querySelector("#pgErr").textContent = T("PIN ไม่ถูกต้อง ลองอีกครั้ง", "Incorrect PIN, try again");
          gateEl.querySelector(".pg-panel").classList.add("pg-shake");
          setTimeout(() => gateEl.querySelector(".pg-panel")?.classList.remove("pg-shake"), 400);
        }
      }
    });
  }

  function enterAs(user, profile) {
    window.activeProfile = profile;
    window.__jcResidentProfileVerified = true;
    sessionStorage.setItem("juristicActiveProfile", profile.id);
    closeGate();
    window.__jcShowAppOriginal(user);
    const chip = document.querySelector("#userChip .user-name, .user-chip .user-name");
    if (chip) chip.textContent = `${profile.name} · ${user.room || user.name}`;
  }

  /* ---------- Hook: ครอบ showApp เดิม ---------- */
  function showResidentProfileGate(user) {
    if (!user || user.role !== "resident") return;
    sessionStorage.removeItem("juristicActiveProfile");
    window.activeProfile = null;
    window.__jcResidentProfileVerified = false;
    document.querySelector("#interfacePickerModal")?.classList.add("hidden");
    document.querySelector("#compactAppView")?.classList.add("hidden");
    document.querySelector("#appView")?.classList.add("hidden");
    document.querySelector("#authView")?.classList.add("hidden");

    const profiles = roomProfiles(user.id);
    openGate();
    if (!profiles.length) return renderCreateProfile(user, true);
    const lastId = localStorage.getItem(LAST_KEY(user.id));
    const last = profiles.find(p => p.id === lastId);
    if (last) return renderPinPad(user, last, true);
    renderPicker(user);
  }

  function install() {
    if (typeof showApp !== "function") return setTimeout(install, 50);
    window.__jcShowAppOriginal = showApp;
    showApp = function (user) {
      if (!user || user.role !== "resident") return window.__jcShowAppOriginal(user);
      showResidentProfileGate(user);
    };
    /* คืน session โปรไฟล์เมื่อรีเฟรชหน้า */
    const sid = sessionStorage.getItem("juristicUser");
    sessionStorage.removeItem("juristicActiveProfile");
    window.activeProfile = null;
    window.__jcResidentProfileVerified = false;
    setTimeout(() => {
      const signedInResident = (typeof currentUser !== "undefined" && currentUser?.role === "resident")
        ? currentUser
        : (sid && typeof getUser === "function" ? getUser(sid) : null);
      const appVisible = !document.querySelector("#appView")?.classList.contains("hidden");
      const compactVisible = !!document.querySelector("#compactAppView") && !document.querySelector("#compactAppView").classList.contains("hidden");
      const gateVisible = !!document.querySelector("#profileGate") && !document.querySelector("#profileGate").classList.contains("hidden");
      if (signedInResident?.role === "resident" && (appVisible || compactVisible) && !gateVisible) {
        showResidentProfileGate(signedInResident);
      }
    }, 0);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", install);
  else install();
})();
