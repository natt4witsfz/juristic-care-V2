#!/usr/bin/env node
"use strict";

import fs from "node:fs";
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

const worker = `const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "X-Frame-Options": "DENY",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()"
};

function withHeaders(response) {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(SECURITY_HEADERS)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    let response = await env.ASSETS.fetch(request);

    if (response.status === 404 && !url.pathname.includes(".")) {
      response = await env.ASSETS.fetch(new Request(new URL("/index.html", url), request));
    }

    return withHeaders(response);
  }
};
`;

fs.writeFileSync(path.join(server, "index.js"), worker, "utf8");
console.log(`Built ${environment} static Sites bundle in dist/`);
