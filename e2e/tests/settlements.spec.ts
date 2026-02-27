import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getObjectByType,
  getObjectsByType,
  getTestSession,
  setupAuthenticatedPage,
  createResolvedEvent,
  addMemberToWorkspace,
} from '../helpers'

const TEST_EMAIL = 'e2e-settlements@example.com'
const TEST_NAME = 'E2E Settlements User'

// Resolved events use date range 2026-06-01 to 2026-06-07
const DEFAULT_START = '2026-06-01'
const DEFAULT_END = '2026-06-07'

test.describe('Settlements Feature', () => {
  test.describe('Settlements API - Unauthenticated', () => {
    test('all settlement endpoints require auth', async ({ request }) => {
      const fakeId = '00000000-0000-0000-0000-000000000000'
      const responses = await Promise.all([
        request.get(`${API_BASE}/api/settlements?event_id=${fakeId}`),
        request.post(`${API_BASE}/api/settlements`, {
          data: { event_id: fakeId },
        }),
        request.delete(`${API_BASE}/api/settlements/${fakeId}`),
        request.put(`${API_BASE}/api/settlements/transfers/${fakeId}`, {
          data: { paid: true },
        }),
      ])
      for (const response of responses) {
        expect(response.status()).toBe(401)
        const body = await response.json()
        expect(body.error).toBe('Authorization required')
      }
    })
  })

  test.describe('Settlements API - Authenticated', () => {
    let apiContext: APIRequestContext
    let eventId: string

    test.beforeAll(async ({ playwright }) => {
      apiContext = await playwright.request.newContext()
      await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      ;({ eventId } = await createResolvedEvent(
        apiContext,
        'Settlement API Test'
      ))

      // Add an expense so settlement has something to compute
      await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Hotel',
          amount: 100,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('GET /api/settlements returns empty list for event with no settlements', async () => {
      const response = await apiContext.get(
        `${API_BASE}/api/settlements?event_id=${eventId}`
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body).toHaveProperty('objects')
      const settlements = getObjectsByType(body.objects, 'settlement')
      expect(settlements).toHaveLength(0)
    })

    test('full settlement lifecycle: create, toggle paid, delete', async () => {
      // Create settlement
      const createResponse = await apiContext.post(
        `${API_BASE}/api/settlements`,
        { data: { event_id: eventId } }
      )
      expect(createResponse.status()).toBe(201)
      const createBody = await createResponse.json()
      const settlement = getObjectByType(createBody.objects, 'settlement')
      expect(settlement).toHaveProperty('id')
      expect(settlement?.eventId).toBe(eventId)
      const settlementId = settlement!.id

      // Settlement should have transfers
      const transfers = getObjectsByType(
        createBody.objects,
        'settlementTransfer'
      )
      // Single user, single expense → no transfers needed (all settled)
      // This is expected since there's only one attendee

      // Read — settlement appears in GET
      const getResponse = await apiContext.get(
        `${API_BASE}/api/settlements?event_id=${eventId}`
      )
      expect(getResponse.ok()).toBeTruthy()
      const getBody = await getResponse.json()
      const listed = getObjectsByType(getBody.objects, 'settlement')
      expect(listed.some((s) => s.id === settlementId)).toBeTruthy()

      // Delete
      const deleteResponse = await apiContext.delete(
        `${API_BASE}/api/settlements/${settlementId}`
      )
      expect(deleteResponse.ok()).toBeTruthy()
      const deleteBody = await deleteResponse.json()
      expect(deleteBody.deleted).toHaveLength(1)
      expect(deleteBody.deleted[0].objectType).toBe('settlement')
      expect(deleteBody.deleted[0].id).toBe(settlementId)
    })

    test('settlement with two users creates transfers that can be toggled paid', async ({
      playwright,
    }) => {
      // Create a new resolved event for this test
      const { eventId: eid } = await createResolvedEvent(
        apiContext,
        'Two User Settlement'
      )

      // Add a second user
      const userBEmail = 'e2e-settle-b@example.com'
      const userBContext = await playwright.request.newContext()
      await getTestSession(userBContext, userBEmail, 'Settle User B')

      const wsResp = await apiContext.get(`${API_BASE}/api/workspaces`)
      const wsBody = await wsResp.json()
      const workspace = getObjectByType(wsBody.objects, 'workspace')!

      await addMemberToWorkspace(apiContext, workspace.id, userBEmail)

      // User B RSVPs as attending
      await userBContext.post(`${API_BASE}/api/events/${eid}/rsvps`, {
        data: { attending: true },
      })

      // User A adds an expense
      await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eid,
          description: 'Shared dinner',
          amount: 80,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })

      // Create settlement — should produce transfers
      const createResp = await apiContext.post(`${API_BASE}/api/settlements`, {
        data: { event_id: eid },
      })
      expect(createResp.status()).toBe(201)
      const createBody = await createResp.json()
      const transfers = getObjectsByType(
        createBody.objects,
        'settlementTransfer'
      )
      expect(transfers.length).toBeGreaterThan(0)

      // Find the transfer where User B pays User A
      const transfer = transfers[0]!
      expect(transfer.paidAt).toBeNull()

      // The recipient (to_user_id) should be able to mark as paid
      // Toggle paid — need the right context based on who is the recipient
      const recipientId = transfer.toUserId as string
      const recipientIsA = recipientId === (await getCurrentUserId(apiContext))

      const recipientContext = recipientIsA ? apiContext : userBContext
      const toggleResp = await recipientContext.put(
        `${API_BASE}/api/settlements/transfers/${transfer.id}`,
        { data: { paid: true } }
      )
      expect(toggleResp.ok()).toBeTruthy()
      const toggleBody = await toggleResp.json()
      const updated = getObjectByType(toggleBody.objects, 'settlementTransfer')
      expect(updated?.paidAt).not.toBeNull()

      // Toggle back to unpaid
      const untoggleResp = await recipientContext.put(
        `${API_BASE}/api/settlements/transfers/${transfer.id}`,
        { data: { paid: false } }
      )
      expect(untoggleResp.ok()).toBeTruthy()
      const untoggleBody = await untoggleResp.json()
      const unpaid = getObjectByType(untoggleBody.objects, 'settlementTransfer')
      expect(unpaid?.paidAt).toBeNull()

      await userBContext.dispose()
    })
  })

  test.describe('Settlements UI', () => {
    let sessionToken: string
    let apiContext: APIRequestContext

    test.beforeAll(async ({ playwright }) => {
      apiContext = await playwright.request.newContext()
      const { token } = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      sessionToken = token
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('settle up button creates settlement and shows transfers', async ({
      page,
    }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'UI Settlement Test'
      )

      // Add an expense
      await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Taxi',
          amount: 30,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      // Wait for page to load
      await expect(
        page.getByRole('heading', { name: 'Settlements' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Click "Preview settlement"
      await expect(
        page.getByRole('button', { name: /Preview settlement/ })
      ).toBeVisible()
      await page.getByRole('button', { name: /Preview settlement/ }).click()

      // Preview modal should appear
      await expect(page.getByText('This is a preview')).toBeVisible()

      // Confirm the settlement
      await page.getByRole('button', { name: /Confirm/ }).click()

      // Settlement should appear with "Settled by" text
      await expect(page.getByText(/Settled by/)).toBeVisible()
    })

    test('delete settlement removes it from the page', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Delete Settlement UI'
      )

      await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Groceries',
          amount: 50,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })

      // Create settlement via API
      await apiContext.post(`${API_BASE}/api/settlements`, {
        data: { event_id: eventId },
      })

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      // Wait for settlement to be visible
      await expect(page.getByText(/Settled by/)).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Delete it
      const [deleteResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/settlements/') &&
            resp.request().method() === 'DELETE'
        ),
        page.getByTestId('delete-settlement-button').click(),
      ])
      expect(deleteResp.ok()).toBeTruthy()

      // Preview settlement button should reappear (expenses are unsettled again)
      await expect(
        page.getByRole('button', { name: /Preview settlement/ })
      ).toBeVisible()
    })
  })
})

async function getCurrentUserId(
  apiContext: APIRequestContext
): Promise<string> {
  const meResp = await apiContext.get(`${API_BASE}/api/auth/me`)
  const meBody = await meResp.json()
  return meBody.user_id
}
