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

// Helper to make authenticated API requests
function authHeaders(token: string): { Authorization: string } {
  return { Authorization: `Bearer ${token}` }
}

// Helper to set up authenticated page
async function setupAuthenticatedPage(
  page: Page,
  token: string
): Promise<void> {
  await page.goto('/')
  await page.evaluate((t) => {
    localStorage.setItem('session_token', t)
  }, token)
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
      const { token } = await getTestSession(request)

      const response = await request.put(
        `${API_BASE}/api/users/00000000-0000-0000-0000-000000000000`,
        {
          headers: authHeaders(token),
          data: { name: 'Hacked Name' },
        }
      )
      // Will be 404 (user not found) or 403 depending on order of checks
      expect([403, 404]).toContain(response.status())
    })

    test('PUT /api/users/:id returns 400 when name is empty', async ({
      request,
    }) => {
      const { token, userId } = await getTestSession(request)

      const response = await request.put(`${API_BASE}/api/users/${userId}`, {
        headers: authHeaders(token),
        data: { name: '' },
      })
      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('Name is required')
    })

    test('PUT /api/users/:id successfully updates name', async ({
      request,
    }) => {
      const { token, userId } = await getTestSession(request)

      const response = await request.put(`${API_BASE}/api/users/${userId}`, {
        headers: authHeaders(token),
        data: { name: 'Updated Profile Name' },
      })
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const updatedUser = getObjectByType(body.objects, 'user')
      expect(updatedUser).toBeTruthy()
      expect(updatedUser!.name).toBe('Updated Profile Name')
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
