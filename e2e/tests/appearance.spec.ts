import { test, expect, APIRequestContext } from '@playwright/test'
import {
  PAGE_LOAD_TIMEOUT,
  getTestSession,
  setupAuthenticatedPage,
  newApiContext,
} from '../helpers'

const TEST_EMAIL = 'e2e-appearance@example.com'
const TEST_NAME = 'E2E Appearance User'

// `dark` as a class-attribute regex would also match Tailwind's static
// `dark:` utilities on <html>; ask the class list directly instead.
function isDark(page: import('@playwright/test').Page) {
  return () =>
    page.evaluate(() => document.documentElement.classList.contains('dark'))
}

test.describe('Appearance settings', () => {
  let sessionToken: string
  let apiContext: APIRequestContext

  test.beforeAll(async ({ playwright }) => {
    apiContext = await newApiContext(playwright)
    const { token } = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
    sessionToken = token
  })

  test.afterAll(async () => {
    await apiContext.dispose()
  })

  test('picks a theme that survives a reload, and can go back to automatic', async ({
    page,
  }) => {
    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/settings')

    await expect(
      page.locator('[data-testid="settings-nav-group"][data-group="personal"]')
    ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

    await page.getByRole('link', { name: 'Appearance' }).click()
    await expect(page).toHaveURL(/\/settings\/appearance$/)

    await page.getByRole('radio', { name: 'Dark' }).check()
    await expect.poll(isDark(page)).toBe(true)

    await page.reload()
    await expect.poll(isDark(page)).toBe(true)
    await expect(page.getByRole('radio', { name: 'Dark' })).toBeChecked()

    // The browser reports a light device, so automatic must drop back to light
    // — the state the old navbar toggle could never return to.
    await page.getByRole('radio', { name: 'Automatic' }).check()
    await expect.poll(isDark(page)).toBe(false)
  })
})
