import { test, expect } from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getTestSession,
  setupAuthenticatedPage,
} from '../helpers'

const TEST_EMAIL = 'e2e-auth-test@example.com'

test.describe('Authentication', () => {
  test('login page: displays form, submits known and unknown emails with success', async ({
    page,
  }) => {
    await page.goto('/login')

    // Displays the login form
    await expect(page.getByTestId('login-title')).toContainText(
      'Sign in to Tayaway'
    )
    await expect(page.getByTestId('email-input')).toBeVisible()
    await expect(page.getByTestId('submit-button')).toBeVisible()

    // Shows success message after requesting magic link for known email
    await page.getByTestId('email-input').fill(TEST_EMAIL)
    await page.getByTestId('submit-button').click()
    await expect(page.getByTestId('success-message')).toBeVisible()

    // Shows success message for unknown email too (no enumeration)
    await page.goto('/login')
    await page.getByTestId('email-input').fill('unknown@example.com')
    await page.getByTestId('submit-button').click()
    await expect(page.getByTestId('success-message')).toBeVisible()
  })

  test('magic link verification: shows errors for missing params and invalid token', async ({
    page,
  }) => {
    // Missing parameters
    await page.goto('/auth/verify')
    await expect(page.getByTestId('verify-error')).toBeVisible()

    // Invalid token
    await page.goto('/auth/verify?token=invalid&email=test@example.com')
    await page.getByTestId('confirm-sign-in').click()
    await expect(page.getByTestId('verify-error')).toBeVisible()
    await expect(
      page.getByRole('link', { name: 'Back to login' })
    ).toBeVisible()
  })

  test('complete magic link request flow', async ({ page, request }) => {
    // Step 1: Request magic link via API
    const magicLinkResponse = await request.post(
      `${API_BASE}/api/auth/magic-link`,
      {
        data: { email: TEST_EMAIL },
      }
    )
    expect(magicLinkResponse.ok()).toBeTruthy()

    // Step 2: Visit home page - should redirect to login (not authenticated)
    await page.goto('/')
    await expect(page).toHaveURL('/login')

    // Step 3: Request magic link via UI
    await page.getByTestId('email-input').fill(TEST_EMAIL)
    await page.getByTestId('submit-button').click()
    await expect(page.getByTestId('success-message')).toBeVisible()
  })

  test('authenticated user sees their email and can logout', async ({
    page,
    request,
  }) => {
    const authEmail = 'e2e-auth-session@example.com'
    const { token } = await getTestSession(request, authEmail, 'Test User')
    await setupAuthenticatedPage(page, token)

    // Navigate to home page - should now be authenticated
    await page.goto('/')
    await expect(page.getByTestId('page-title')).toContainText('Dashboard', {
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // User menu should show their email initial
    await expect(page.getByTestId('user-initial')).toBeVisible()
    await expect(page.getByTestId('user-initial')).toHaveText('E') // First letter of email

    // Click user menu and logout
    await page.getByTestId('user-menu-button').click()
    // Wait for dropdown menu to be visible
    await expect(page.getByText(authEmail)).toBeVisible()
    await page.getByTestId('sign-out-button').click()

    // Should redirect to login
    await expect(page).toHaveURL('/login')
  })

  test('magic-link endpoint: returns success for any email and error for missing email', async ({
    request,
  }) => {
    // Returns success regardless of email existence (parallel requests)
    const [knownResponse, unknownResponse] = await Promise.all([
      request.post(`${API_BASE}/api/auth/magic-link`, {
        data: { email: TEST_EMAIL },
      }),
      request.post(`${API_BASE}/api/auth/magic-link`, {
        data: { email: 'nonexistent@example.com' },
      }),
    ])

    expect(knownResponse.ok()).toBeTruthy()
    expect(unknownResponse.ok()).toBeTruthy()

    const [knownBody, unknownBody] = await Promise.all([
      knownResponse.json(),
      unknownResponse.json(),
    ])
    expect(knownBody.message).toContain('If an account exists')
    expect(unknownBody.message).toContain('If an account exists')

    // Returns error for missing email
    const missingResponse = await request.post(
      `${API_BASE}/api/auth/magic-link`,
      {
        data: {},
      }
    )
    expect(missingResponse.status()).toBe(400)
    const missingBody = await missingResponse.json()
    expect(missingBody.error).toBe('Email is required')
  })

  test('verify/me/logout endpoints: return errors for invalid or missing auth', async ({
    request,
  }) => {
    // All four requests are independent - fire in parallel
    const [verifyInvalid, verifyMissing, meNoAuth, meInvalid, logoutNoAuth] =
      await Promise.all([
        request.post(`${API_BASE}/api/auth/verify`, {
          data: { token: 'invalid-token', email: TEST_EMAIL },
        }),
        request.post(`${API_BASE}/api/auth/verify`, {
          data: {},
        }),
        request.get(`${API_BASE}/api/auth/me`),
        request.get(`${API_BASE}/api/auth/me`, {
          headers: { Cookie: 'session_token=invalid-token' },
        }),
        request.post(`${API_BASE}/api/auth/logout`),
      ])

    // Verify with invalid token
    expect(verifyInvalid.status()).toBe(401)
    const verifyInvalidBody = await verifyInvalid.json()
    expect(verifyInvalidBody.error).toBe('Invalid or expired magic link')

    // Verify with missing params
    expect(verifyMissing.status()).toBe(400)
    const verifyMissingBody = await verifyMissing.json()
    expect(verifyMissingBody.error).toBe('Token is required')

    // /me without auth header
    expect(meNoAuth.status()).toBe(401)
    const meNoAuthBody = await meNoAuth.json()
    expect(meNoAuthBody.error).toBe('Authorization required')

    // /me with invalid session cookie
    expect(meInvalid.status()).toBe(401)
    const meInvalidBody = await meInvalid.json()
    expect(meInvalidBody.error).toBe('Authorization required')

    // /logout without auth header
    expect(logoutNoAuth.status()).toBe(401)
    const logoutNoAuthBody = await logoutNoAuth.json()
    expect(logoutNoAuthBody.error).toBe('Authorization required')
  })

  test('home page redirects to login when not authenticated', async ({
    page,
  }) => {
    await page.goto('/')
    await expect(page).toHaveURL('/login')
  })

  test('login page stays on login with invalid session cookie', async ({
    page,
  }) => {
    // Set a fake session cookie (won't be valid but tests the redirect logic)
    await page.context().addCookies([
      {
        name: 'session_token',
        value: 'fake-token',
        domain: 'localhost',
        path: '/',
        httpOnly: true,
        sameSite: 'Lax',
      },
    ])

    // The login page checks isAuthenticated which requires a valid session
    // With a fake cookie, the /me call will fail
    await page.goto('/login')

    // Should stay on login since the fake token is invalid
    await expect(page.getByTestId('login-title')).toContainText(
      'Sign in to Tayaway'
    )
  })
})
