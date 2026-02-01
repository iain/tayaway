import { test, expect } from '@playwright/test'

test.describe('Homepage', () => {
  test('displays the application title', async ({ page }) => {
    await page.goto('/')
    await expect(page.locator('h1')).toContainText('Tayaway')
  })

  test('shows API health status', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByText('API Status: healthy')).toBeVisible()
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
