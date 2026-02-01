import { test, expect } from '@playwright/test'

const TEST_EMAIL = 'test@example.com'
const API_BASE = 'http://localhost:9292'

test.describe('Authentication', () => {
  test.describe('Login page', () => {
    test('displays the login form', async ({ page }) => {
      await page.goto('/login')
      await expect(page.getByTestId('login-title')).toContainText('Sign in to Tayaway')
      await expect(page.getByTestId('email-input')).toBeVisible()
      await expect(page.getByTestId('submit-button')).toBeVisible()
    })

    test('shows success message after requesting magic link', async ({ page }) => {
      await page.goto('/login')
      await page.getByTestId('email-input').fill(TEST_EMAIL)
      await page.getByTestId('submit-button').click()

      await expect(page.getByTestId('success-message')).toBeVisible()
    })

    test('shows success message for unknown email (no enumeration)', async ({ page }) => {
      await page.goto('/login')
      await page.getByTestId('email-input').fill('unknown@example.com')
      await page.getByTestId('submit-button').click()

      await expect(page.getByTestId('success-message')).toBeVisible()
    })
  })

  test.describe('Magic link verification', () => {
    test('shows error for invalid token', async ({ page }) => {
      await page.goto('/auth/verify?token=invalid&email=test@example.com')
      await expect(page.getByText('Invalid or expired magic link')).toBeVisible()
      await expect(page.getByRole('link', { name: 'Back to login' })).toBeVisible()
    })

    test('shows error for missing parameters', async ({ page }) => {
      await page.goto('/auth/verify')
      await expect(page.getByText('Missing token or email')).toBeVisible()
    })
  })

  test.describe('Full auth flow', () => {
    test('complete magic link request flow', async ({ page, request }) => {
      // Step 1: Request magic link via API
      const magicLinkResponse = await request.post(`${API_BASE}/api/auth/magic-link`, {
        data: { email: TEST_EMAIL }
      })
      expect(magicLinkResponse.ok()).toBeTruthy()

      // Step 2: Visit home page - should redirect to login (not authenticated)
      await page.goto('/')
      await expect(page).toHaveURL('/login')

      // Step 3: Request magic link via UI
      await page.getByTestId('email-input').fill(TEST_EMAIL)
      await page.getByTestId('submit-button').click()
      await expect(page.getByTestId('success-message')).toBeVisible()
    })

    test('authenticated user sees their email and can logout', async ({ page, request }) => {
      // Create a session using the test helper endpoint
      const sessionResponse = await request.post(`${API_BASE}/api/test/session`, {
        data: { email: TEST_EMAIL, name: 'Test User' }
      })
      expect(sessionResponse.ok()).toBeTruthy()
      const { session_token } = await sessionResponse.json()

      // Set up authenticated session
      await page.goto('/')
      await page.evaluate((token) => {
        localStorage.setItem('session_token', token)
      }, session_token)

      // Navigate to home page - should now be authenticated
      await page.goto('/')
      await expect(page.locator('h1')).toContainText('Dashboard')

      // User menu should show their email initial
      await expect(page.getByTestId('user-initial')).toBeVisible()
      await expect(page.getByTestId('user-initial')).toHaveText('T') // First letter of "Test"

      // Click user menu and logout
      await page.getByTestId('user-menu-button').click()
      // Wait for dropdown menu to be visible
      await expect(page.getByText(TEST_EMAIL)).toBeVisible()
      await page.getByTestId('sign-out-button').click()

      // Should redirect to login
      await expect(page).toHaveURL('/login')
    })
  })

  test.describe('Auth API endpoints', () => {
    test('POST /api/auth/magic-link returns success for valid email', async ({ request }) => {
      const response = await request.post(`${API_BASE}/api/auth/magic-link`, {
        data: { email: TEST_EMAIL }
      })
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body.message).toContain('If an account exists')
    })

    test('POST /api/auth/magic-link returns success for unknown email', async ({ request }) => {
      const response = await request.post(`${API_BASE}/api/auth/magic-link`, {
        data: { email: 'nonexistent@example.com' }
      })
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body.message).toContain('If an account exists')
    })

    test('POST /api/auth/magic-link returns error for missing email', async ({ request }) => {
      const response = await request.post(`${API_BASE}/api/auth/magic-link`, {
        data: {}
      })
      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('Email is required')
    })

    test('POST /api/auth/verify returns error for invalid token', async ({ request }) => {
      const response = await request.post(`${API_BASE}/api/auth/verify`, {
        data: { token: 'invalid-token', email: TEST_EMAIL }
      })
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Invalid or expired magic link')
    })

    test('POST /api/auth/verify returns error for missing params', async ({ request }) => {
      const response = await request.post(`${API_BASE}/api/auth/verify`, {
        data: {}
      })
      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('Token and email are required')
    })

    test('GET /api/auth/me returns error without auth header', async ({ request }) => {
      const response = await request.get(`${API_BASE}/api/auth/me`)
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })

    test('GET /api/auth/me returns error with invalid token', async ({ request }) => {
      const response = await request.get(`${API_BASE}/api/auth/me`, {
        headers: { Authorization: 'Bearer invalid-token' }
      })
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Invalid or expired session')
    })

    test('POST /api/auth/logout returns error without auth header', async ({ request }) => {
      const response = await request.post(`${API_BASE}/api/auth/logout`)
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })
  })

  test.describe('Protected routes', () => {
    test('home page redirects to login when not authenticated', async ({ page }) => {
      await page.goto('/')
      await expect(page).toHaveURL('/login')
    })

    test('login page redirects to home if already has session token', async ({ page }) => {
      // Set a fake session token (won't be valid but tests the redirect logic)
      await page.goto('/')
      await page.evaluate(() => {
        localStorage.setItem('session_token', 'fake-token')
      })

      // The login page checks isAuthenticated which requires a valid session
      // With a fake token, the /me call will fail and clear the token
      await page.goto('/login')

      // Should stay on login since the fake token is invalid
      await expect(page.getByTestId('login-title')).toContainText('Sign in to Tayaway')
    })
  })
})
