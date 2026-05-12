import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  globalSetup: './e2e/global-setup.ts',
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
    baseURL: 'http://localhost:5174',
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
  webServer: [
    {
      command: 'mise run //backend:dev:e2e',
      url: 'http://localhost:9293/health',
      reuseExistingServer: false,
      timeout: 120000,
      stdout: 'pipe',
      stderr: 'pipe',
    },
    {
      command: 'mise run //frontend:dev:e2e',
      url: 'http://localhost:5174',
      reuseExistingServer: false,
      timeout: 120000,
      stdout: 'pipe',
      stderr: 'pipe',
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
      stdout: 'pipe',
      stderr: 'pipe',
    },
  ],
})
