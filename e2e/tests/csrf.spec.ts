import { test, expect } from '@playwright/test'
import { API_BASE, getTestSession } from '../helpers'
import { PROTOCOL_VERSION } from '../../frontend/src/api/protocolVersion'

const TEST_EMAIL = 'e2e-csrf@example.com'
const TEST_NAME = 'E2E CSRF User'

test.describe('CSRF Protection', () => {
  test('authenticated POST without CSRF header returns 403', async ({
    playwright,
  }) => {
    // Create a context without the CSRF header (overriding the global
    // extraHTTPHeaders) — but still past the protocol version gate, which
    // answers 426 before CSRF gets a look-in.
    const ctx = await playwright.request.newContext({
      extraHTTPHeaders: { 'X-Client-Version': String(PROTOCOL_VERSION) },
    })

    // Establish a session — the test endpoint does not require the CSRF header
    await getTestSession(ctx, TEST_EMAIL, TEST_NAME)

    // Now make an authenticated request without the CSRF header
    const response = await ctx.post(`${API_BASE}/api/events`, {
      data: { name: 'Should Fail' },
    })

    expect(response.status()).toBe(403)
    const body = await response.json()
    expect(body.error).toBe('Forbidden')

    await ctx.dispose()
  })
})
