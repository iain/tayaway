import { test, expect } from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getTestSession,
  setupAuthenticatedPage,
} from '../helpers'

const TEST_NAME = 'E2E Email Change User'

test.describe('Email Change Feature', () => {
  test.describe('Email Change API', () => {
    test('request endpoint requires auth, validates same/taken email', async ({
      request,
    }) => {
      // 401 without auth
      const noAuth = await request.post(
        `${API_BASE}/api/users/email-change/request`,
        { data: { email: 'new@example.com' } }
      )
      expect(noAuth.status()).toBe(401)

      // Setup: two users, one to change, one to block
      const userEmail = `e2e-ec-api-${crypto.randomUUID()}@example.com`
      const takenEmail = `e2e-ec-taken-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, userEmail, TEST_NAME)
      await getTestSession(request, takenEmail, 'Other User')
      const headers = { Cookie: `session_token=${token}` }

      // Success
      const ok = await request.post(
        `${API_BASE}/api/users/email-change/request`,
        {
          data: { email: `new-${crypto.randomUUID()}@example.com` },
          headers,
        }
      )
      expect(ok.ok()).toBeTruthy()
      expect((await ok.json()).message).toContain(
        'verification link has been sent'
      )

      // Same email
      const same = await request.post(
        `${API_BASE}/api/users/email-change/request`,
        { data: { email: userEmail }, headers }
      )
      expect(same.status()).toBe(400)
      expect((await same.json()).error).toContain('different')

      // Taken email
      const taken = await request.post(
        `${API_BASE}/api/users/email-change/request`,
        { data: { email: takenEmail }, headers }
      )
      expect(taken.status()).toBe(400)
      expect((await taken.json()).error).toContain('already in use')
    })

    test('verify endpoint does not require auth and validates tokens', async ({
      request,
    }) => {
      // Invalid JWT
      const invalid = await request.post(
        `${API_BASE}/api/users/email-change/verify`,
        { data: { token: 'invalid-jwt' } }
      )
      expect(invalid.status()).toBe(401)
      expect((await invalid.json()).error).toContain('Invalid or expired')

      // Missing token
      const missing = await request.post(
        `${API_BASE}/api/users/email-change/verify`,
        { data: {} }
      )
      expect(missing.status()).toBe(400)
      expect((await missing.json()).error).toContain('Token is required')
    })
  })

  test.describe('Email Change UI', () => {
    test('Edit button opens change email modal with correct content', async ({
      page,
      request,
    }) => {
      const email = `e2e-ec-modal-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, email, TEST_NAME)
      await setupAuthenticatedPage(page, token)
      await page.goto('/account')

      const editButton = page.getByTestId('edit-email-button')
      await expect(editButton).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      await editButton.click()

      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(
        page.getByRole('dialog').getByRole('heading', { name: 'Change Email' })
      ).toBeVisible()
      await expect(
        page.getByRole('dialog').getByText('Enter your new email address')
      ).toBeVisible()
    })

    test('submitting email change request closes modal and shows success', async ({
      page,
      request,
    }) => {
      const email = `e2e-ec-submit-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, email, TEST_NAME)
      await setupAuthenticatedPage(page, token)
      await page.goto('/account')

      await expect(page.getByTestId('edit-email-button')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await page.getByTestId('edit-email-button').click()
      await expect(page.getByRole('dialog')).toBeVisible()

      await page
        .getByLabel('New email address')
        .fill(`e2e-ec-new-${crypto.randomUUID()}@example.com`)

      await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/users/email-change/request') &&
            resp.request().method() === 'POST' &&
            resp.ok()
        ),
        page.getByRole('dialog').getByTestId('submit-button').click(),
      ])

      await expect(page.getByRole('dialog')).toBeHidden()
      await expect(page.getByTestId('email-change-success')).toBeVisible()
    })

    test('verify-email page handles missing and invalid tokens', async ({
      page,
    }) => {
      // Missing token
      await page.goto('/verify-email')
      await expect(page.getByTestId('email-change-error')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Invalid token — shows confirm button, then error after click
      await page.goto('/verify-email?token=bad-token')
      await expect(page.getByTestId('confirm-email-change')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await page.getByTestId('confirm-email-change').click()

      await expect(page.getByTestId('error-message')).toBeVisible()
    })
  })
})
