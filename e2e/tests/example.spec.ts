import { test, expect } from '@playwright/test'

const API_BASE = 'http://localhost:9292'

// Helper to get an authenticated session for testing
async function getTestSession(request: typeof test extends { info: () => infer R } ? R extends { request: infer Q } ? Q : never : never) {
  const response = await request.post(`${API_BASE}/api/test/session`, {
    data: { email: 'example-test@example.com', name: 'Example Test' }
  })
  const body = await response.json()
  return body.session_token
}

test.describe('Homepage', () => {
  test('displays the dashboard when authenticated', async ({ page, request }) => {
    const token = await getTestSession(request)
    await page.goto('/')
    await page.evaluate((t) => localStorage.setItem('session_token', t), token)
    await page.goto('/')

    await expect(page.locator('h1')).toContainText('Dashboard')
  })

  test('shows API health status when authenticated', async ({ page, request }) => {
    const token = await getTestSession(request)
    await page.goto('/')
    await page.evaluate((t) => localStorage.setItem('session_token', t), token)
    await page.goto('/')

    await expect(page.getByText('Status: healthy')).toBeVisible()
  })

  test('redirects to login when not authenticated', async ({ page }) => {
    await page.goto('/')
    await expect(page).toHaveURL('/login')
  })
})

test.describe('Health endpoint', () => {
  test('returns healthy status', async ({ request }) => {
    const response = await request.get('http://localhost:9292/health')
    expect(response.ok()).toBeTruthy()
    expect(await response.json()).toEqual({ status: 'healthy' })
  })

  test('API proxy returns healthy status', async ({ request }) => {
    const response = await request.get('/api/health')
    expect(response.ok()).toBeTruthy()
    expect(await response.json()).toEqual({ status: 'healthy' })
  })
})
