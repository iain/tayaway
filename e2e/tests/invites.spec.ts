import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getTestSession,
  setupAuthenticatedPage,
  getWorkspaceId,
  newApiContext,
} from '../helpers'

const TEST_EMAIL = 'e2e-invites@example.com'
const TEST_NAME = 'E2E Invites User'

test.describe('Workspace Invites Feature', () => {
  test.describe('Invites API - Unauthenticated', () => {
    test('authenticated invite endpoints require auth', async ({ request }) => {
      const fakeId = '00000000-0000-0000-0000-000000000000'
      const responses = await Promise.all([
        request.get(`${API_BASE}/api/invites?workspace_id=${fakeId}`),
        request.post(`${API_BASE}/api/invites`, {
          data: { email: 'test@example.com', workspace_id: fakeId },
        }),
        request.delete(
          `${API_BASE}/api/invites/${fakeId}?workspace_id=${fakeId}`
        ),
      ])
      for (const response of responses) {
        expect(response.status()).toBe(401)
        const body = await response.json()
        expect(body.error).toBe('Authorization required')
      }
    })

    test('info endpoint returns 400 for missing token', async ({ request }) => {
      const response = await request.get(`${API_BASE}/api/invites/info`)
      expect(response.status()).toBe(400)
    })

    test('info endpoint returns error for invalid token', async ({
      request,
    }) => {
      const response = await request.get(
        `${API_BASE}/api/invites/info?token=invalid-jwt`
      )
      expect([400, 410]).toContain(response.status())
    })

    test('accept endpoint returns error for invalid token', async ({
      request,
    }) => {
      const response = await request.post(`${API_BASE}/api/invites/accept`, {
        data: { token: 'invalid-jwt' },
      })
      expect(response.status()).toBeGreaterThanOrEqual(400)
    })
  })

  test.describe('Invites API - Authenticated', () => {
    let apiContext: APIRequestContext
    let workspaceId: string

    test.beforeAll(async ({ playwright }) => {
      apiContext = await newApiContext(playwright)
      await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      workspaceId = await getWorkspaceId(apiContext)
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('GET /api/invites returns list of pending invites', async () => {
      const response = await apiContext.get(
        `${API_BASE}/api/invites?workspace_id=${workspaceId}`
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body).toHaveProperty('objects')
      expect(Array.isArray(body.objects)).toBeTruthy()
    })

    test('full invite lifecycle: create, list, cancel', async () => {
      const inviteEmail = `invite-lifecycle-${Date.now()}@example.com`

      // Create invite
      const createResponse = await apiContext.post(`${API_BASE}/api/invites`, {
        data: {
          email: inviteEmail,
          workspace_id: workspaceId,
          name: 'Invited Person',
        },
      })
      expect(createResponse.status()).toBe(201)
      const createBody = await createResponse.json()
      expect(createBody).toHaveProperty('objects')
      const inviteObj = createBody.objects.find(
        (o: { objectType: string }) => o.objectType === 'workspaceInvite'
      )
      expect(inviteObj.email).toBe(inviteEmail)
      const inviteId = inviteObj.id

      // List — invite should appear
      const listResponse = await apiContext.get(
        `${API_BASE}/api/invites?workspace_id=${workspaceId}`
      )
      expect(listResponse.ok()).toBeTruthy()
      const listBody = await listResponse.json()
      expect(
        listBody.objects.some(
          (i: { id: string; objectType: string }) =>
            i.id === inviteId && i.objectType === 'workspaceInvite'
        )
      ).toBeTruthy()

      // Cancel invite
      const cancelResponse = await apiContext.delete(
        `${API_BASE}/api/invites/${inviteId}?workspace_id=${workspaceId}`
      )
      expect(cancelResponse.ok()).toBeTruthy()
      const cancelBody = await cancelResponse.json()
      expect(cancelBody.deleted).toEqual([
        { objectType: 'workspaceInvite', id: inviteId },
      ])
    })

    test('POST /api/invites requires email', async () => {
      const response = await apiContext.post(`${API_BASE}/api/invites`, {
        data: { workspace_id: workspaceId },
      })
      expect(response.status()).toBe(400)
    })

    test('POST /api/invites rejects already existing member', async () => {
      // The test user (TEST_EMAIL) is already a member
      const response = await apiContext.post(`${API_BASE}/api/invites`, {
        data: {
          email: TEST_EMAIL,
          workspace_id: workspaceId,
        },
      })
      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBeTruthy()
    })
  })

  test.describe('Invites UI', () => {
    let sessionToken: string
    let apiContext: APIRequestContext
    let workspaceId: string

    test.beforeAll(async ({ playwright }) => {
      apiContext = await newApiContext(playwright)
      const { token } = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      sessionToken = token
      workspaceId = await getWorkspaceId(apiContext)
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('invite modal: open, fill in, and submit creates pending invite', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/settings/workspaces/${workspaceId}/members`)

      // Wait for page to load
      await expect(page.getByTestId('invite-member-button')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Open invite modal
      await page.getByTestId('invite-member-button').click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(
        page.getByRole('dialog').getByRole('heading', { name: 'Invite Member' })
      ).toBeVisible()

      // Fill in the form
      const inviteEmail = `invite-ui-${Date.now()}@example.com`
      await page.getByLabel('Name').fill('UI Test Person')
      await page.getByLabel('Email').fill(inviteEmail)

      // Submit
      const [inviteResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/invites') &&
            resp.request().method() === 'POST' &&
            resp.ok()
        ),
        page.getByTestId('submit-button').click(),
      ])
      expect(inviteResp.status()).toBe(201)

      // Modal should close
      await expect(page.getByRole('dialog')).not.toBeVisible()

      // Pending invite should appear
      await expect(page.getByTestId('pending-invites-section')).toBeVisible()
      await expect(page.getByText(inviteEmail)).toBeVisible()
    })

    test('cancel invite removes it from the pending list', async ({ page }) => {
      // Create an invite via API first
      const inviteEmail = `invite-cancel-ui-${Date.now()}@example.com`
      await apiContext.post(`${API_BASE}/api/invites`, {
        data: {
          email: inviteEmail,
          workspace_id: workspaceId,
          name: 'Cancel Test',
        },
      })

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/settings/workspaces/${workspaceId}/members`)

      // Wait for pending invites section
      await expect(page.getByTestId('pending-invites-section')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(page.getByText(inviteEmail)).toBeVisible()

      // Cancel the invite
      const inviteRow = page
        .getByTestId('pending-invites-section')
        .locator('li')
        .filter({ hasText: inviteEmail })
      await inviteRow.getByTestId('cancel-invite-button').click()

      // The invite should disappear
      await expect(page.getByText(inviteEmail)).not.toBeVisible()
    })
  })

  test.describe('Invite Accept Page', () => {
    test('shows error for missing token', async ({ page }) => {
      await page.goto('/invite/accept')
      await expect(page.getByText('Missing token')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
    })

    test('shows error for invalid token', async ({ page }) => {
      await page.goto('/invite/accept?token=bad-token')
      await expect(page.getByText(/no longer valid/)).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
    })
  })
})
