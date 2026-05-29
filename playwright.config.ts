import { defineConfig, devices } from '@playwright/test'

// When PLAYWRIGHT_BASE_URL is set we're testing a deployed stack (the edge
// container on new.tayaway.nl, or the containerised-e2e CI stack) rather than
// the local dev servers: point at it and skip the webServer block (no
// localhost processes to spawn).
//
// globalSetup POSTs /api/test/reset, which only exists when the backend runs
// under_test (test/e2e). Against a *production* target those routes are 404,
// so skip it there. The containerised-e2e CI stack runs in MISE_ENV=e2e, so
// the routes ARE live — E2E_CONTAINERISED flags that case so globalSetup (and
// the data-driven specs) run. smoke.spec.ts inverts the same flag: it asserts
// real LetsEncrypt TLS, so it runs only against the prod target, not CI.
const remoteBaseURL = process.env.PLAYWRIGHT_BASE_URL
const containerised = !!process.env.E2E_CONTAINERISED

export default defineConfig({
  globalSetup: remoteBaseURL && !containerised ? undefined : './e2e/global-setup.ts',
  testDir: './e2e/tests',
  // Containerised mode runs only a stack-smoke subset — the specs that exercise
  // integration points the dev-server e2e can't: the Caddy /api proxy + DB
  // round-trip (events), the /ws upgrade + LISTEN/NOTIFY realtime path (voting's
  // "appears via WebSocket"), session cookies through the proxy while Falcon
  // runs read-only (auth), and CSRF semantics (csrf). The remaining specs are
  // app-logic the normal e2e already covers in full — re-running all of them
  // through Caddy is cost without signal. Widen this list if a new spec starts
  // depending on stack behaviour.
  testMatch: containerised
    ? [
        '**/auth.spec.ts',
        '**/events.spec.ts',
        '**/voting.spec.ts',
        '**/csrf.spec.ts',
      ]
    : undefined,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 1,
  workers: process.env.CI ? 2 : 4,
  reporter: [['html', { open: 'never' }], ['dot']],
  expect: {
    timeout: 5_000,
  },
  use: {
    baseURL: remoteBaseURL ?? 'http://localhost:5174',
    locale: 'en-US',
    trace: 'on-first-retry',
    extraHTTPHeaders: {
      'X-CSRF-Protection': '1',
    },
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: remoteBaseURL
    ? undefined
    : [
    {
      command: 'mise run //backend:dev:e2e',
      url: 'http://localhost:9293/health',
      reuseExistingServer: false,
      timeout: 120000,
      stdout: 'ignore',
      stderr: 'ignore',
    },
    {
      command: 'mise run //frontend:dev:e2e',
      url: 'http://localhost:5174',
      reuseExistingServer: false,
      timeout: 120000,
      stdout: 'ignore',
      stderr: 'ignore',
    },
    // Production-built preview server used by tests that need a real service
    // worker (e.g. offline cold-launch). vite preview serves dist/ statically
    // and proxies /api and /ws to the e2e backend via the `preview.proxy`
    // config in frontend/vite.config.ts.
    {
      command: 'mise run //frontend:preview:e2e',
      url: 'http://localhost:5175',
      reuseExistingServer: false,
      timeout: 120000,
      stdout: 'ignore',
      stderr: 'ignore',
    },
  ],
})
