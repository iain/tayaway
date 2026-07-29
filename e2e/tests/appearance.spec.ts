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
    // — the state the old navbar toggle could never return to. Exact match:
    // the formats group below also has an option whose name starts with
    // "Automatic".
    await page.getByRole('radio', { name: 'Automatic', exact: true }).check()
    await expect.poll(isDark(page)).toBe(false)
  })

  // The radio is a 16px dot and its label is a 24px line — too small to hit
  // reliably on a phone. Each row bleeds 8px above and below into a ~40px
  // target, so a tap that lands in the gap still counts.
  test('selects a theme from the padding above the label text', async ({
    page,
  }) => {
    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/settings/appearance')

    const label = page.locator('label[for="theme-dark"]')
    await expect(label).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

    const box = (await label.boundingBox())!
    // 6px above the label's top edge: outside the text, inside the target.
    await page.mouse.click(box.x + box.width / 2, box.y - 6)

    await expect(page.getByRole('radio', { name: 'Dark' })).toBeChecked()
    await expect.poll(isDark(page)).toBe(true)
  })
})
