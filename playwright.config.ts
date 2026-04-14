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
      command:
        'cd backend && RACK_ENV=e2e bundle exec falcon serve --bind http://localhost:9293 --threaded',
      url: 'http://localhost:9293/health',
      reuseExistingServer: !process.env.CI,
      timeout: 120000,
      stdout: 'ignore',
      stderr: 'ignore',
    },
    {
      command: 'cd frontend && FRONTEND_PORT=5174 API_PORT=9293 pnpm run dev',
      url: 'http://localhost:5174',
      reuseExistingServer: !process.env.CI,
      timeout: 120000,
      stdout: 'ignore',
      stderr: 'ignore',
    },
    // Production-built preview server used by tests that need a real service
    // worker (e.g. offline cold-launch). vite preview serves dist/ statically
    // and proxies /api and /ws to the e2e backend via the `preview.proxy`
    // config in frontend/vite.config.ts.
    {
      command:
        'cd frontend && FRONTEND_PREVIEW_PORT=5175 API_PORT=9293 pnpm run build && FRONTEND_PREVIEW_PORT=5175 API_PORT=9293 pnpm exec vite preview --strictPort',
      url: 'http://localhost:5175',
      reuseExistingServer: !process.env.CI,
      timeout: 120000,
      stdout: 'ignore',
      stderr: 'ignore',
    },
  ],
})
