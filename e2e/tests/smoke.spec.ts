import { test, expect } from '@playwright/test'

// Edge/stack smoke. Runs ONLY against a deployed stack (PLAYWRIGHT_BASE_URL
// set) — never the local dev webServer — because it asserts Caddy-specific
// behaviour the vite dev server doesn't reproduce: the carried-over security
// headers, immutable asset caching, and /api + /ws proxying. No auth and no
// test-only routes, so it's safe to run against production.
//
// Run it with:
//   PLAYWRIGHT_BASE_URL=https://new.tayaway.nl \
//     pnpm exec playwright test e2e/tests/smoke.spec.ts
//
// The data-driven specs can't run here (they need /api/test/*, disabled in
// production) — those belong to the containerised-e2e CI job that brings the
// stack up in MISE_ENV=e2e.
test.skip(
  !process.env.PLAYWRIGHT_BASE_URL || !!process.env.E2E_CONTAINERISED,
  'edge smoke runs only against a real deployed stack with trusted TLS — not the local containerised-e2e stack, which serves plain http',
)

test.describe('edge stack smoke', () => {
  test('serves the SPA over a trusted TLS cert', async ({ page }) => {
    // Navigating over https at all proves the cert chains to a trusted root —
    // Playwright rejects untrusted certs by default, so this also confirms
    // we're on real Let's Encrypt, not the staging endpoint.
    await page.goto('/')
    await expect(page).toHaveTitle(/Tayaway/)
    await expect(page.locator('#app')).toBeAttached()
  })

  test('sets the carried-over security headers', async ({ request }) => {
    const res = await request.get('/')
    expect(res.status()).toBe(200)
    const h = res.headers()
    expect(h['strict-transport-security']).toContain('max-age=')
    expect(h['x-content-type-options']).toBe('nosniff')
    expect(h['x-frame-options']).toBe('DENY')
    expect(h['referrer-policy']).toBe('strict-origin-when-cross-origin')
    expect(h['permissions-policy']).toContain('geolocation=(self)')
    // The two third-party origins that had to survive the nginx -> Caddy move.
    const csp = h['content-security-policy'] ?? ''
    expect(csp).toContain('https://photon.komoot.io')
    expect(csp).toContain('https://*.tile.openstreetmap.org')
  })

  test('serves hashed assets immutably', async ({ request }) => {
    const html = await (await request.get('/')).text()
    const asset = html.match(/\/assets\/[^"']+\.(?:js|css)/)?.[0]
    expect(asset, 'index.html should reference a hashed /assets/ file').toBeTruthy()
    const res = await request.get(asset!)
    expect(res.status()).toBe(200)
    expect(res.headers()['cache-control']).toContain('immutable')
  })

  test('proxies /api to the backend rather than the SPA fallthrough', async ({ request }) => {
    // The SPA catch-all serves index.html with 200 for any unknown path. An
    // unknown /api path coming back 404 therefore proves Caddy routed it to
    // the backend instead of falling through to the SPA.
    const res = await request.get('/api/__smoke_probe__')
    expect(res.status()).toBe(404)
  })

  test('serves the real backend health check at /health', async ({ request }) => {
    // Caddy proxies /health to the backend (it lives at /health, not under
    // /api), so this is the DB-checked status as JSON — not the SPA shell
    // that any unproxied path would return.
    const res = await request.get('/health')
    expect(res.status()).toBe(200)
    expect(res.headers()['content-type'] ?? '').toContain('application/json')
    expect(await res.json()).toMatchObject({ status: 'healthy' })
  })

  test('routes /ws to the backend rather than the SPA fallthrough', async ({ request }) => {
    // A plain GET to /ws (no Upgrade header) reaches the backend's ws route,
    // which rejects it as unauthenticated JSON — not the SPA HTML shell.
    const res = await request.get('/ws')
    expect(res.status()).toBe(401)
    expect(res.headers()['content-type'] ?? '').toContain('application/json')
  })
})
