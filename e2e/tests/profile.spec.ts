import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getObjectByType,
  getTestSession,
  setupAuthenticatedPage,
} from '../helpers'

const TEST_EMAIL = 'e2e-profile@example.com'
const TEST_NAME = 'E2E Profile User'

test.describe('Profile Feature', () => {
  test.describe('Profile API', () => {
    let apiContext: APIRequestContext
    let userId: string

    test.beforeAll(async ({ playwright }) => {
      apiContext = await playwright.request.newContext()
      const session = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      userId = session.userId
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('update name lifecycle: 401 without auth, 403/404 for other user, 400 for empty name, success', async ({
      request,
    }) => {
      // 401 without auth
      const unauthResponse = await request.put(
        `${API_BASE}/api/users/some-id`,
        {
          data: { name: 'New Name' },
        }
      )
      expect(unauthResponse.status()).toBe(401)
      const unauthBody = await unauthResponse.json()
      expect(unauthBody.error).toBe('Authorization required')

      // 403/404 when updating another user
      const otherUserResponse = await apiContext.put(
        `${API_BASE}/api/users/00000000-0000-0000-0000-000000000000`,
        {
          data: { name: 'Hacked Name' },
        }
      )
      // Will be 404 (user not found) or 403 depending on order of checks
      expect([403, 404]).toContain(otherUserResponse.status())

      // 400 when name is empty
      const emptyNameResponse = await apiContext.put(
        `${API_BASE}/api/users/${userId}`,
        {
          data: { name: '' },
        }
      )
      expect(emptyNameResponse.status()).toBe(400)
      const emptyNameBody = await emptyNameResponse.json()
      expect(emptyNameBody.error).toBe('Name is required')

      // Success update
      const successResponse = await apiContext.put(
        `${API_BASE}/api/users/${userId}`,
        {
          data: { name: 'Updated Profile Name' },
        }
      )
      expect(successResponse.ok()).toBeTruthy()
      const successBody = await successResponse.json()
      const updatedMember = getObjectByType(successBody.objects, 'member')
      expect(updatedMember).toBeTruthy()
      expect(updatedMember!.name).toBe('Updated Profile Name')
    })
  })

  test.describe('Profile UI', () => {
    let token: string

    test.beforeAll(async ({ playwright }) => {
      const apiContext = await playwright.request.newContext()
      const session = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      token = session.token
      await apiContext.dispose()
    })

    test('displays profile info, opens edit modal, and updates name', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, token)
      await page.goto('/profile')

      // Profile page displays name and email
      await expect(page.getByTestId('account-info-heading')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(page.getByText(TEST_EMAIL)).toBeVisible()

      // Edit button opens pre-filled name modal
      const editButton = page.getByTestId('edit-name-button')
      await expect(editButton).toBeVisible()
      await editButton.click()

      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(
        page.getByRole('dialog').getByRole('heading', { name: 'Edit Name' })
      ).toBeVisible()

      // Clear and type new name
      const input = page.getByLabel('Name')
      await input.clear()
      await input.fill('New E2E Name')

      // Save and wait for the API response
      await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/users/') &&
            resp.request().method() === 'PUT'
        ),
        page.getByRole('button', { name: 'Save' }).click(),
      ])

      // Modal should close
      await expect(page.getByRole('dialog')).toBeHidden()

      // Updated name should appear on the profile page
      await expect(page.getByText('New E2E Name')).toBeVisible()
    })

    test('can end a non-current session from the sessions list', async ({
      page,
      request,
    }) => {
      // Use a unique email so this test's sessions don't interfere with others
      const sessionEmail = `e2e-profile-sessions-${crypto.randomUUID()}@example.com`

      // Create two sessions so there's at least one non-current session
      const { token: currentToken } = await getTestSession(
        request,
        sessionEmail,
        TEST_NAME
      )
      await getTestSession(request, sessionEmail, TEST_NAME)

      // Authenticate as the current session and visit profile
      await setupAuthenticatedPage(page, currentToken)
      await page.goto('/profile')

      // Should see the Active Sessions section with current badge
      await expect(page.getByTestId('active-sessions-heading')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(page.getByTestId('current-session-badge')).toBeVisible()

      // Should see exactly one "End session" button (for the other session we created)
      const endButtons = page.getByRole('button', { name: 'End session' })
      await expect(endButtons).toHaveCount(1)

      // Click the "End session" button
      await endButtons.first().click()

      // The session should be removed from the list
      await expect(endButtons).toHaveCount(0)

      // Current session badge should still be visible (we didn't delete our own)
      await expect(page.getByTestId('current-session-badge')).toBeVisible()
    })
  })
})
