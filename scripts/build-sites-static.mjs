#!/usr/bin/env node
"use strict";

import fs from "node:fs";
import crypto from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const dist = path.join(root, "dist");
const server = path.join(dist, "server");
const args = process.argv.slice(2);
const environmentIndex = args.indexOf("--environment");
const environment = environmentIndex === -1 ? "production" : args[environmentIndex + 1];
const allowedEnvironments = new Set(["preproduction", "production"]);

if (!allowedEnvironments.has(environment)) {
  console.error("Environment must be preproduction or production");
  process.exit(1);
}

function failPromotionGuard() {
  console.error("Production promotion requires a valid Bit code.");
  process.exit(1);
}

function verifyProductionPromotionGuard() {
  if (environment !== "production") return;
  const expectedHash = process.env.PRODUCTION_PROMOTION_BIT_HASH || "";
  const bitCode = process.env.PRODUCTION_PROMOTION_BIT_CODE || "";
  const confirmation = process.env.PRODUCTION_PROMOTION_CONFIRM || "";

  if (!/^[a-f0-9]{64}$/i.test(expectedHash)) failPromotionGuard();
  if (!bitCode || /[\r\n\t]/.test(bitCode)) failPromotionGuard();
  if (confirmation !== "PROMOTE_TO_PRODUCTION") failPromotionGuard();

  const actualHash = crypto.createHash("sha256").update(bitCode, "utf8").digest("hex");
  const expected = Buffer.from(expectedHash.toLowerCase(), "hex");
  const actual = Buffer.from(actualHash, "hex");
  if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) {
    failPromotionGuard();
  }
}

verifyProductionPromotionGuard();

const files = [
  "index.html",
  "styles.css",
  "app.js",
  "profiles.js",
  "supabase-client.js",
  "config.js",
  "js/security.js"
];

fs.rmSync(dist, { recursive: true, force: true });
fs.mkdirSync(server, { recursive: true });

for (const file of files) {
  const from = path.join(root, file);
  const to = path.join(dist, file);
  fs.mkdirSync(path.dirname(to), { recursive: true });
  if (file === "index.html" && environment === "preproduction") {
    const html = fs.readFileSync(from, "utf8");
    const banner = `<div style="position:fixed;left:0;right:0;top:0;z-index:99999;background:#7c2d12;color:#fff;font:600 13px/1.4 system-ui,-apple-system,Segoe UI,sans-serif;text-align:center;padding:8px 12px;box-shadow:0 2px 8px rgba(0,0,0,.16)">PRE-PRODUCTION - สำหรับทดสอบก่อนขึ้น Production</div><style>body{padding-top:34px}</style>`;
    fs.writeFileSync(to, html.replace("<body>", `<body>${banner}`), "utf8");
  } else {
    fs.copyFileSync(from, to);
  }
}

const hostingConfig = path.join(root, ".openai", `hosting.${environment}.json`);
const hostingOut = path.join(dist, ".openai", "hosting.json");
fs.mkdirSync(path.dirname(hostingOut), { recursive: true });
fs.copyFileSync(hostingConfig, hostingOut);

const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8"
};

const staticAssets = {};
for (const file of files) {
  const route = `/${file.replace(/\\\\/g, "/")}`;
  const ext = path.extname(file);
  staticAssets[route] = {
    contentType: contentTypes[ext] || "application/octet-stream",
    body: fs.readFileSync(path.join(dist, file), "utf8")
  };
}

const worker = `const SECURITY_HEADERS = {
  "Content-Security-Policy": "default-src 'self'; script-src 'self' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com data:; img-src 'self' data: blob: https:; connect-src 'self' https://*.supabase.co https://script.google.com https://script.googleusercontent.com; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'; upgrade-insecure-requests",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "X-Frame-Options": "DENY",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()"
};

const STATIC_ASSETS = ${JSON.stringify(staticAssets)};

function responseFor(asset, status = 200) {
  const headers = new Headers({ "Content-Type": asset.contentType });
  for (const [key, value] of Object.entries(SECURITY_HEADERS)) {
    headers.set(key, value);
  }
  return new Response(asset.body, { status, headers });
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    let pathname = decodeURIComponent(url.pathname);
    if (pathname === "/") pathname = "/index.html";

    if (pathname.includes("..")) {
      return responseFor({ body: "Not found", contentType: "text/plain; charset=utf-8" }, 404);
    }

    const asset = STATIC_ASSETS[pathname] || (!pathname.includes(".") ? STATIC_ASSETS["/index.html"] : null);
    if (!asset) {
      return responseFor({ body: "Not found", contentType: "text/plain; charset=utf-8" }, 404);
    }
    return responseFor(asset);
  }
};
`;

fs.writeFileSync(path.join(server, "index.js"), worker, "utf8");
console.log(`Built ${environment} static Sites bundle in dist/`);
