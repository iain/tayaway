import { defineConfig, devices } from '@playwright/test'

// When PLAYWRIGHT_BASE_URL is set we're testing a deployed stack (the edge
// container on new.tayaway.nl, or the containerised-e2e CI stack) rather than
// the local dev servers: point at it, and skip both the webServer block (no
// localhost processes to spawn) and globalSetup (the /api/test/reset it POSTs
// to is disabled in production). Only smoke.spec.ts is meant to run in this
// mode — the data-driven specs need the test-only routes.
const remoteBaseURL = process.env.PLAYWRIGHT_BASE_URL

export default defineConfig({
  globalSetup: remoteBaseURL ? undefined : './e2e/global-setup.ts',
  testDir: './e2e/tests',
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
