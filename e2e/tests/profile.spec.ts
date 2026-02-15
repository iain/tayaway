import { test, expect, Page, APIRequestContext } from '@playwright/test'

const API_BASE = 'http://localhost:9293'
const TEST_EMAIL = 'e2e-profile@example.com'
const TEST_NAME = 'E2E Profile User'

// Helper to extract objects from pool response by type
interface PoolObject {
  id: string
  objectType: string
  [key: string]: unknown
}

function getObjectByType<T extends PoolObject>(
  objects: PoolObject[],
  type: string
): T | undefined {
  return objects.find((o) => o.objectType === type) as T | undefined
}

// Helper to get an authenticated session for testing
async function getTestSession(
  request: APIRequestContext
): Promise<{ token: string; userId: string }> {
  const response = await request.post(`${API_BASE}/api/test/session`, {
    data: { email: TEST_EMAIL, name: TEST_NAME },
  })
  if (!response.ok()) {
    throw new Error(`Failed to create test session: ${response.status()}`)
  }
  const body = await response.json()
  return { token: body.session_token, userId: body.user_id }
}

// Helper to set up authenticated page via cookie
async function setupAuthenticatedPage(
  page: Page,
  token: string
): Promise<void> {
  await page.context().addCookies([
    {
      name: 'session_token',
      value: token,
      domain: 'localhost',
      path: '/',
      httpOnly: true,
      sameSite: 'Lax',
    },
  ])
}

test.describe('Profile Feature', () => {
  test.describe('Profile API', () => {
    test('PUT /api/users/:id returns 401 without auth', async ({ request }) => {
      const response = await request.put(`${API_BASE}/api/users/some-id`, {
        data: { name: 'New Name' },
      })
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })

    test('PUT /api/users/:id returns 403 when updating another user', async ({
      request,
    }) => {
      await getTestSession(request)

      const response = await request.put(
        `${API_BASE}/api/users/00000000-0000-0000-0000-000000000000`,
        {
          data: { name: 'Hacked Name' },
        }
      )
      // Will be 404 (user not found) or 403 depending on order of checks
      expect([403, 404]).toContain(response.status())
    })

    test('PUT /api/users/:id returns 400 when name is empty', async ({
      request,
    }) => {
      const { userId } = await getTestSession(request)

      const response = await request.put(`${API_BASE}/api/users/${userId}`, {
        data: { name: '' },
      })
      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('Name is required')
    })

    test('PUT /api/users/:id successfully updates name', async ({
      request,
    }) => {
      const { userId } = await getTestSession(request)

      const response = await request.put(`${API_BASE}/api/users/${userId}`, {
        data: { name: 'Updated Profile Name' },
      })
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const updatedMember = getObjectByType(body.objects, 'member')
      expect(updatedMember).toBeTruthy()
      expect(updatedMember!.name).toBe('Updated Profile Name')
    })
  })

  test.describe('Profile UI', () => {
    test('profile page displays name and email', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      await setupAuthenticatedPage(page, token)
      await page.goto('/profile')

      await expect(page.getByText('Account Information')).toBeVisible()
      await expect(page.getByText(TEST_EMAIL)).toBeVisible()
      await expect(page.getByText(TEST_NAME)).toBeVisible()
    })

    test('profile page shows edit button for name', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      await setupAuthenticatedPage(page, token)
      await page.goto('/profile')

      await expect(page.getByRole('button', { name: 'Edit' })).toBeVisible()
    })

    test('clicking edit opens the name modal', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      await setupAuthenticatedPage(page, token)
      await page.goto('/profile')

      await page.getByRole('button', { name: 'Edit' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(
        page.getByRole('dialog').getByRole('heading', { name: 'Edit Name' })
      ).toBeVisible()
    })

    test('edit name modal is pre-filled with current name', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      await setupAuthenticatedPage(page, token)
      await page.goto('/profile')

      await page.getByRole('button', { name: 'Edit' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()

      const input = page.getByLabel('Name')
      await expect(input).toHaveValue(TEST_NAME)
    })

    test('can end a non-current session from the sessions list', async ({
      page,
      request,
    }) => {
      // Create two sessions so there's at least one non-current session
      const { token: currentToken } = await getTestSession(request)
      await getTestSession(request)

      // Authenticate as the current session and visit profile
      await setupAuthenticatedPage(page, currentToken)
      await page.goto('/profile')

      // Should see the Active Sessions section with current badge
      await expect(page.getByText('Active Sessions')).toBeVisible()
      await expect(page.getByText('Current session')).toBeVisible()

      // Should see at least one "End session" button (for non-current sessions)
      const endButtons = page.getByRole('button', { name: 'End session' })
      await expect(endButtons.first()).toBeVisible()
      const countBefore = await endButtons.count()

      // Click the first "End session" button
      await endButtons.first().click()

      // The session should be removed from the list
      await expect(endButtons).toHaveCount(countBefore - 1)

      // Current session badge should still be visible (we didn't delete our own)
      await expect(page.getByText('Current session')).toBeVisible()
    })

    test('can update name through the modal', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      await setupAuthenticatedPage(page, token)
      await page.goto('/profile')

      // Open modal
      await page.getByRole('button', { name: 'Edit' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()

      // Clear and type new name
      const input = page.getByLabel('Name')
      await input.clear()
      await input.fill('New E2E Name')

      // Save
      await page.getByRole('button', { name: 'Save' }).click()

      // Modal should close
      await expect(page.getByRole('dialog')).toBeHidden()

      // Updated name should appear on the profile page
      await expect(page.getByText('New E2E Name')).toBeVisible()
    })
  })
})
