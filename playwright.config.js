// Playwright config scaffolded for the team.
// The npm registry / browser download was unreachable in the Stage 0 build
// environment, so e2e specs are marked test.skip and cannot run here yet.
// Enable by: npm install && npx playwright install, then `npx playwright test`.
const { defineConfig } = require("@playwright/test");

module.exports = defineConfig({
  testDir: "./test/e2e",
  timeout: 30000,
  use: {
    baseURL: "http://localhost:4173",
    headless: true
  },
  webServer: {
    command: "python3 -m http.server 4173",
    port: 4173,
    reuseExistingServer: true
  }
});
