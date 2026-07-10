/* =====================================================
   Juristic Care — Security helpers (Stage 0)
   Dual module: usable as a browser global (window.JuristicSecurity)
   and as a Node CommonJS module (require) for tests. No DOM access.
   ===================================================== */
(function (root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.JuristicSecurity = api;
  // eslint-disable-next-line no-undef
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const HTML_ESCAPES = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;"
  };

  // Escape a value for safe insertion into HTML text or double/single-quoted
  // attribute context. Identical output contract to app.js `esc()`.
  function escapeHtml(value) {
    return String(value === undefined || value === null ? "" : value)
      .replace(/[&<>"']/g, (char) => HTML_ESCAPES[char]);
  }

  // Cryptographically-strong temporary password.
  // Excludes ambiguous chars (0/O/1/l/I). Guarantees >=1 letter and >=1 digit.
  const PW_LETTERS = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz";
  const PW_DIGITS = "23456789";
  const PW_ALL = PW_LETTERS + PW_DIGITS;

  function randomInt(maxExclusive) {
    // Prefer Web Crypto (present in browsers and Node >=19 as global crypto).
    const c = (typeof globalThis !== "undefined" && globalThis.crypto) || null;
    if (c && typeof c.getRandomValues === "function") {
      const buf = new Uint32Array(1);
      // Rejection sampling to avoid modulo bias.
      const limit = Math.floor(0xffffffff / maxExclusive) * maxExclusive;
      let x = 0;
      do {
        c.getRandomValues(buf);
        x = buf[0];
      } while (x >= limit);
      return x % maxExclusive;
    }
    // Last-resort fallback (should not happen in supported runtimes).
    return Math.floor(Math.random() * maxExclusive);
  }

  function pick(chars) {
    return chars[randomInt(chars.length)];
  }

  function generateTempPassword(length) {
    const len = Math.max(8, Number(length) || 10);
    const out = [pick(PW_LETTERS), pick(PW_DIGITS)];
    for (let i = out.length; i < len; i++) out.push(pick(PW_ALL));
    // Shuffle (Fisher–Yates) so the guaranteed letter/digit aren't fixed.
    for (let i = out.length - 1; i > 0; i--) {
      const j = randomInt(i + 1);
      const tmp = out[i];
      out[i] = out[j];
      out[j] = tmp;
    }
    return out.join("");
  }

  // Seeded demo accounts. In non-demo (real backend) mode these must not
  // authenticate. Used for demo-account isolation.
  const DEMO_ACCOUNT_CODES = [
    "ADMIN",
    "STAFF-01",
    "STAFF-02",
    "STAFF-03",
    "STAFF-04",
    "STAFF-05",
    "STAFF-06",
    "A-0201"
  ];

  function isDemoAccount(code) {
    return DEMO_ACCOUNT_CODES.includes(String(code || "").trim().toUpperCase());
  }

  return {
    escapeHtml,
    generateTempPassword,
    isDemoAccount,
    DEMO_ACCOUNT_CODES
  };
});
