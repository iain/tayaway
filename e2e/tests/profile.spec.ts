import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getObjectByType,
  getTestSession,
  setupAuthenticatedPage,
  newApiContext,
} from '../helpers'

const TEST_EMAIL = 'e2e-profile@example.com'
const TEST_NAME = 'E2E Profile User'

test.describe('Profile Feature', () => {
  test.describe('Profile API', () => {
    let apiContext: APIRequestContext
    let userId: string

    test.beforeAll(async ({ playwright }) => {
      apiContext = await newApiContext(playwright)
      const session = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      userId = session.userId
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('update contact fields: phone, birthday, location', async () => {
      // Update phone
      const phoneResponse = await apiContext.put(
        `${API_BASE}/api/users/${userId}`,
        {
          data: { name: TEST_NAME, phoneNumber: '+31612345678' },
        }
      )
      expect(phoneResponse.ok()).toBeTruthy()
      const phoneBody = await phoneResponse.json()
      const phoneMember = getObjectByType(phoneBody.objects, 'member')
      expect(phoneMember!.phoneNumber).toBe('+31612345678')

      // Update birthday
      const bdayResponse = await apiContext.put(
        `${API_BASE}/api/users/${userId}`,
        {
          data: { name: TEST_NAME, birthday: '1990-06-15' },
        }
      )
      expect(bdayResponse.ok()).toBeTruthy()
      const bdayBody = await bdayResponse.json()
      const bdayMember = getObjectByType(bdayBody.objects, 'member')
      expect(bdayMember!.birthday).toBe('1990-06-15')

      // Update location with coordinates
      const locResponse = await apiContext.put(
        `${API_BASE}/api/users/${userId}`,
        {
          data: {
            name: TEST_NAME,
            locationName: 'Berlin, Germany',
            latitude: 52.52,
            longitude: 13.405,
          },
        }
      )
      expect(locResponse.ok()).toBeTruthy()
      const locBody = await locResponse.json()
      const locMember = getObjectByType(locBody.objects, 'member')
      expect(locMember!.locationName).toBe('Berlin, Germany')
      expect(locMember!.latitude).toBeCloseTo(52.52, 1)
      expect(locMember!.longitude).toBeCloseTo(13.405, 1)

      // Clear phone
      const clearPhoneResponse = await apiContext.put(
        `${API_BASE}/api/users/${userId}`,
        {
          data: { name: TEST_NAME, phoneNumber: '' },
        }
      )
      expect(clearPhoneResponse.ok()).toBeTruthy()
      const clearPhoneBody = await clearPhoneResponse.json()
      const clearPhoneMember = getObjectByType(clearPhoneBody.objects, 'member')
      expect(clearPhoneMember!.phoneNumber).toBeNull()

      // Invalid birthday
      const badBdayResponse = await apiContext.put(
        `${API_BASE}/api/users/${userId}`,
        {
          data: { name: TEST_NAME, birthday: 'not-a-date' },
        }
      )
      expect(badBdayResponse.status()).toBe(400)
      const badBdayBody = await badBdayResponse.json()
      expect(badBdayBody.error).toBe('Invalid birthday format')

      // Set all contact fields at once and verify /me returns them
      const allFieldsResponse = await apiContext.put(
        `${API_BASE}/api/users/${userId}`,
        {
          data: {
            name: TEST_NAME,
            phoneNumber: '+44123456789',
            birthday: '1985-03-20',
            locationName: 'London, UK',
            latitude: 51.5074,
            longitude: -0.1278,
          },
        }
      )
      expect(allFieldsResponse.ok()).toBeTruthy()

      const meResponse = await apiContext.get(`${API_BASE}/api/auth/me`)
      expect(meResponse.ok()).toBeTruthy()
      const meBody = await meResponse.json()
      expect(meBody.phoneNumber).toBe('+44123456789')
      expect(meBody.birthday).toBe('1985-03-20')
      expect(meBody.locationName).toBe('London, UK')
      expect(meBody.latitude).toBeCloseTo(51.5074, 1)
      expect(meBody.longitude).toBeCloseTo(-0.1278, 1)
    })

    test('update IBAN: set, verify in /me, clear, reject invalid', async () => {
      // Set valid IBAN
      const setResponse = await apiContext.put(
        `${API_BASE}/api/users/${userId}`,
        {
          data: { name: TEST_NAME, iban: 'NL91ABNA0417164300' },
        }
      )
      expect(setResponse.ok()).toBeTruthy()

      // Verify in /me
      const meResponse = await apiContext.get(`${API_BASE}/api/auth/me`)
      expect(meResponse.ok()).toBeTruthy()
      const meBody = await meResponse.json()
      expect(meBody.iban).toBe('NL91 •••• •••• 4300')

      // Clear IBAN
      const clearResponse = await apiContext.put(
        `${API_BASE}/api/users/${userId}`,
        {
          data: { name: TEST_NAME, iban: '' },
        }
      )
      expect(clearResponse.ok()).toBeTruthy()
      const clearMeResponse = await apiContext.get(`${API_BASE}/api/auth/me`)
      expect(clearMeResponse.ok()).toBeTruthy()
      const clearMeBody = await clearMeResponse.json()
      expect(clearMeBody.iban).toBeNull()

      // Reject invalid IBAN
      const invalidResponse = await apiContext.put(
        `${API_BASE}/api/users/${userId}`,
        {
          data: { name: TEST_NAME, iban: 'NL00FAKE1234567890' },
        }
      )
      expect(invalidResponse.status()).toBe(400)
      const invalidBody = await invalidResponse.json()
      expect(invalidBody.error).toContain('Invalid IBAN')
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
      const apiContext = await newApiContext(playwright)
      const session = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      token = session.token
      await apiContext.dispose()
    })

    test('displays profile info, edits name inline, and updates', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, token)
      await page.goto('/settings/profile')

      // Profile page displays the About you section heading
      await expect(
        page.getByRole('heading', { name: 'About you' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Edit button triggers inline editing
      const editButton = page.getByTestId('edit-name-button')
      await expect(editButton).toBeVisible()
      await editButton.click()

      // Clear and type new name in the inline input
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

      // Updated name should appear on the profile page
      await expect(page.getByText('New E2E Name').first()).toBeVisible()
    })

    test('displays contact fields and can edit them inline', async ({
      page,
      request,
    }) => {
      // Use a unique user for this test to avoid conflicts
      const contactEmail = `e2e-profile-contact-${crypto.randomUUID()}@example.com`
      const { token: contactToken, userId: contactUserId } =
        await getTestSession(request, contactEmail, 'Contact Test')

      // Set initial contact fields via API
      await request.put(`${API_BASE}/api/users/${contactUserId}`, {
        data: {
          name: 'Contact Test',
          phoneNumber: '+31600000000',
          birthday: '1990-01-15',
        },
      })

      await setupAuthenticatedPage(page, contactToken)
      await page.goto('/settings/profile')

      // Wait for the page to load
      await expect(
        page.getByRole('heading', { name: 'About you' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Verify contact fields are displayed
      await expect(page.getByText('+31600000000')).toBeVisible()
      await expect(page.getByText('01/15/1990')).toBeVisible()

      // Click edit contact button to trigger inline editing
      await page.getByTestId('edit-contact-button').click()

      // Update phone number inline
      const phoneInput = page.getByLabel('Phone')
      await phoneInput.clear()
      await phoneInput.fill('+31611111111')

      // Save and wait for the API response
      await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/users/') &&
            resp.request().method() === 'PUT'
        ),
        page.getByRole('button', { name: 'Save' }).click(),
      ])

      // Updated phone should appear on the profile page
      await expect(page.getByText('+31611111111')).toBeVisible()
    })

    test('can edit IBAN inline on profile', async ({ page, request }) => {
      // Use a unique user for this test
      const ibanEmail = `e2e-profile-iban-${crypto.randomUUID()}@example.com`
      const { token: ibanToken } = await getTestSession(
        request,
        ibanEmail,
        'IBAN Test'
      )

      await setupAuthenticatedPage(page, ibanToken)
      await page.goto('/settings/payment')

      // Wait for the page to load
      await expect(page.getByRole('heading', { name: 'Payment' })).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Click edit IBAN button to trigger inline editing
      await page.getByTestId('edit-iban-button').click()

      // Enter a valid IBAN inline
      const ibanInput = page.getByLabel('IBAN')
      await ibanInput.fill('NL91ABNA0417164300')

      // Save and wait for the API response
      await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/users/') &&
            resp.request().method() === 'PUT'
        ),
        page.getByRole('button', { name: 'Save' }).click(),
      ])

      // Masked IBAN should appear on the profile page
      await expect(page.getByText('NL91 •••• •••• 4300')).toBeVisible()

      // Edit again to clear it
      await page.getByTestId('edit-iban-button').click()

      // Input should start empty (IBAN is masked, not pre-filled)
      const ibanInputAgain = page.getByLabel('IBAN')
      await expect(ibanInputAgain).toHaveValue('')

      // Click "Remove IBAN" to clear it
      await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/users/') &&
            resp.request().method() === 'PUT' &&
            resp.status() === 200
        ),
        page.getByRole('button', { name: 'Remove IBAN' }).click(),
      ])

      // Masked IBAN should no longer be visible
      await expect(page.getByText('NL91 •••• •••• 4300')).not.toBeVisible()
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

      // Authenticate as the current session and visit security page
      await setupAuthenticatedPage(page, currentToken)
      await page.goto('/settings/login')

      // Should see the Active Sessions section with current badge
      await expect(
        page.getByRole('heading', { name: 'Active Sessions' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(page.getByTestId('current-session-badge')).toBeVisible()

      // Should see exactly one "Revoke" button (for the other session we created)
      const endButtons = page.getByRole('button', { name: 'Revoke' })
      await expect(endButtons).toHaveCount(1)

      // Click the "Revoke" button
      await endButtons.first().click()

      // The session should be removed from the list
      await expect(endButtons).toHaveCount(0)

      // Current session badge should still be visible (we didn't delete our own)
      await expect(page.getByTestId('current-session-badge')).toBeVisible()
    })
  })
})
