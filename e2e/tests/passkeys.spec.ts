import {
  test,
  expect,
  APIRequestContext,
  CDPSession,
  Page,
} from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getTestSession,
  setupAuthenticatedPage,
  newApiContext,
} from '../helpers'

const TEST_EMAIL = 'e2e-passkeys@example.com'
const TEST_NAME = 'E2E Passkey User'

/**
 * Adds a virtual authenticator to the page via Chrome DevTools Protocol.
 * Returns the CDP session and authenticator ID for cleanup.
 */
async function addVirtualAuthenticator(
  page: Page
): Promise<{ cdp: CDPSession; authenticatorId: string }> {
  const cdp = await page.context().newCDPSession(page)
  await cdp.send('WebAuthn.enable')
  const { authenticatorId } = await cdp.send(
    'WebAuthn.addVirtualAuthenticator',
    {
      options: {
        protocol: 'ctap2',
        transport: 'internal',
        hasResidentKey: true,
        hasUserVerification: true,
        isUserVerified: true,
      },
    }
  )
  return { cdp, authenticatorId }
}

test.describe('Passkeys', () => {
  test.describe('Passkey API', () => {
    let apiContext: APIRequestContext
    let token: string

    test.beforeAll(async ({ playwright }) => {
      apiContext = await newApiContext(playwright)
      const session = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      token = session.token
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('list passkeys: returns empty array initially', async () => {
      const response = await apiContext.get(`${API_BASE}/api/auth/passkeys`, {
        headers: { Cookie: `session_token=${token}` },
      })
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body.passkeys).toEqual([])
    })

    test('list passkeys: returns 401 without auth', async ({ request }) => {
      const response = await request.get(`${API_BASE}/api/auth/passkeys`)
      expect(response.status()).toBe(401)
    })

    test('register begin: returns creation options', async () => {
      const response = await apiContext.post(
        `${API_BASE}/api/auth/passkeys/register/begin`,
        {
          headers: { Cookie: `session_token=${token}` },
        }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body.options).toHaveProperty('challenge')
      expect(body.options).toHaveProperty('rp')
      expect(body.options).toHaveProperty('user')
      expect(body.challengeToken).toBeTruthy()
    })

    test('authenticate begin: returns request options (no auth required)', async () => {
      const response = await apiContext.post(
        `${API_BASE}/api/auth/passkeys/authenticate/begin`
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body.options).toHaveProperty('challenge')
      expect(body.options).toHaveProperty('rpId')
      expect(body.challengeToken).toBeTruthy()
    })

    test('authenticate complete: returns 401 for invalid challenge', async () => {
      const response = await apiContext.post(
        `${API_BASE}/api/auth/passkeys/authenticate/complete`,
        {
          data: {
            challengeToken: 'invalid',
            credential: { id: 'fake', response: {} },
          },
        }
      )
      expect(response.status()).toBe(401)
    })

    test('delete: returns 404 for non-existent passkey', async () => {
      const response = await apiContext.delete(
        `${API_BASE}/api/auth/passkeys/00000000-0000-0000-0000-000000000000`,
        {
          headers: { Cookie: `session_token=${token}` },
        }
      )
      expect(response.status()).toBe(404)
    })

    test('rename: returns 400 for blank name', async () => {
      const response = await apiContext.put(
        `${API_BASE}/api/auth/passkeys/00000000-0000-0000-0000-000000000000`,
        {
          headers: { Cookie: `session_token=${token}` },
          data: { name: '  ' },
        }
      )
      expect(response.status()).toBe(400)
    })
  })

  test.describe('Passkey UI', () => {
    test('account page shows passkeys section with empty state', async ({
      page,
      request,
    }) => {
      const email = `e2e-passkeys-ui-empty-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, email, 'Passkey Empty')

      await setupAuthenticatedPage(page, token)
      await page.goto('/account')

      await expect(page.getByRole('heading', { name: 'Passkeys' })).toBeVisible(
        { timeout: PAGE_LOAD_TIMEOUT }
      )

      await expect(page.getByText('No passkeys registered')).toBeVisible()
      await expect(
        page.getByRole('button', { name: 'Add passkey' })
      ).toBeVisible()
    })

    test('register a passkey via virtual authenticator and see it in the list', async ({
      page,
      request,
    }) => {
      const email = `e2e-passkeys-register-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, email, 'Passkey Register')

      await setupAuthenticatedPage(page, token)
      await page.goto('/account')

      await expect(page.getByRole('heading', { name: 'Passkeys' })).toBeVisible(
        { timeout: PAGE_LOAD_TIMEOUT }
      )

      const { cdp } = await addVirtualAuthenticator(page)

      // Click "Add passkey" — virtual authenticator auto-completes the ceremony
      await page.getByRole('button', { name: 'Add passkey' }).click()

      // Passkey appears in the list with a default name containing the date
      await expect(page.getByText('Passkey (')).toBeVisible({ timeout: 15_000 })
      await expect(page.getByText('No passkeys registered')).not.toBeVisible()

      await cdp.detach()
    })

    test('rename a passkey via edit button', async ({ page, request }) => {
      const email = `e2e-passkeys-rename-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, email, 'Passkey Rename')

      await setupAuthenticatedPage(page, token)
      await page.goto('/account')

      await expect(page.getByRole('heading', { name: 'Passkeys' })).toBeVisible(
        { timeout: PAGE_LOAD_TIMEOUT }
      )

      const { cdp } = await addVirtualAuthenticator(page)

      // Register a passkey
      await page.getByRole('button', { name: 'Add passkey' }).click()
      await expect(page.getByText('Passkey (')).toBeVisible({ timeout: 15_000 })

      // Click edit button and rename
      await page.getByRole('button', { name: 'Rename passkey' }).click()
      const input = page.getByLabel('Passkey name')
      await expect(input).toBeVisible()
      await input.clear()
      await input.fill('My YubiKey')
      await input.press('Enter')

      // Renamed passkey visible
      await expect(page.getByText('My YubiKey')).toBeVisible()

      await cdp.detach()
    })

    test('register a passkey then delete it', async ({ page, request }) => {
      const email = `e2e-passkeys-delete-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, email, 'Passkey Delete')

      await setupAuthenticatedPage(page, token)
      await page.goto('/account')

      await expect(page.getByRole('heading', { name: 'Passkeys' })).toBeVisible(
        { timeout: PAGE_LOAD_TIMEOUT }
      )

      const { cdp } = await addVirtualAuthenticator(page)

      // Register a passkey
      await page.getByRole('button', { name: 'Add passkey' }).click()
      await expect(page.getByText('Passkey (')).toBeVisible({ timeout: 15_000 })

      // Delete it
      await page.getByRole('button', { name: 'Remove' }).click()

      // Should return to empty state
      await expect(page.getByText('No passkeys registered')).toBeVisible()

      await cdp.detach()
    })

    test('login page shows passkey button', async ({ page }) => {
      await page.goto('/login')

      await expect(page.getByTestId('login-title')).toBeVisible()
      await expect(page.getByTestId('passkey-login-button')).toBeVisible()
      await expect(page.getByTestId('passkey-login-button')).toContainText(
        'Sign in with a passkey'
      )
    })

    test('full passkey registration and login flow', async ({
      page,
      request,
    }) => {
      const email = `e2e-passkeys-login-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, email, 'Passkey Login')

      // Step 1: Register a passkey on the account page
      await setupAuthenticatedPage(page, token)
      await page.goto('/account')

      await expect(page.getByRole('heading', { name: 'Passkeys' })).toBeVisible(
        { timeout: PAGE_LOAD_TIMEOUT }
      )

      const { cdp } = await addVirtualAuthenticator(page)

      await page.getByRole('button', { name: 'Add passkey' }).click()
      await expect(page.getByText('Passkey (')).toBeVisible({ timeout: 15_000 })

      // Step 2: Log out
      await page.getByTestId('user-menu-button').click()
      await page.getByTestId('log-out-button').click()

      // Step 3: The virtual authenticator auto-completes the conditional mediation
      // on the login page, logging us back in immediately. Either we land on login
      // briefly then get redirected to dashboard, or we go straight to dashboard.
      await expect(page.getByTestId('page-title')).toContainText('Dashboard', {
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await cdp.detach()
    })
  })
})
