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
  getWorkspaceId,
  newApiContext,
  offsetDate,
  RESOLVED_EVENT_START,
  RESOLVED_EVENT_END,
} from '../helpers'

const TEST_EMAIL = 'e2e-settlements@example.com'
const TEST_NAME = 'E2E Settlements User'

// Resolved events land on the shared upcoming window (see helpers). Partial
// attendance windows below hang off it via offsetDate so day-overlap maths
// (which expense covers whom) is preserved: day N == offsetDate(13 + N), i.e.
// the old "Jun N". Window spans day 1 (start) … day 7 (end).
const DEFAULT_START = RESOLVED_EVENT_START
const DEFAULT_END = RESOLVED_EVENT_END

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
      apiContext = await newApiContext(playwright)
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
      const userBContext = await newApiContext(playwright)
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
      apiContext = await newApiContext(playwright)
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

      // Click "Start settlement"
      await expect(page.getByTestId('start-settlement-button')).toBeVisible()
      await page.getByTestId('start-settlement-button').click()

      // Preview modal should appear
      await expect(
        page.getByText('Nothing has been settled yet.')
      ).toBeVisible()

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

      // Delete it (confirm dialog before the DELETE fires)
      await page.getByTestId('delete-settlement-button').click()
      const [deleteResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/settlements/') &&
            resp.request().method() === 'DELETE'
        ),
        page.getByTestId('confirm-delete-settlement').click(),
      ])
      expect(deleteResp.ok()).toBeTruthy()

      // Start settlement button should reappear (expenses are unsettled again)
      await expect(page.getByTestId('start-settlement-button')).toBeVisible()
    })

    test('show math expander reveals balances and annotations pre and post settlement', async ({
      page,
      playwright,
    }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Math Expander UI'
      )

      // Add a second attending user so the split has two parties and produces
      // at least one transfer. Pattern mirrors 'Mixed Expense Settlement'.
      const workspaceId = await getWorkspaceId(apiContext)
      const bobContext = await newApiContext(playwright)
      const bobEmail = `e2e-math-bob-${Date.now()}@example.com`
      await getTestSession(bobContext, bobEmail, 'Math Bob')
      await addMemberToWorkspace(apiContext, workspaceId, bobEmail)
      await bobContext.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: {
          attending: true,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })

      // Alice pays €50 groceries for the whole trip → Bob will owe €25.
      await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Groceries',
          amount: 50,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(
        page.getByRole('heading', { name: 'Settlements' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Open preview, expand math.
      await page.getByTestId('start-settlement-button').click()
      await expect(
        page.getByText('Nothing has been settled yet.')
      ).toBeVisible()
      await page.getByTestId('preview-math-toggle').click()
      await expect(page.getByText('Net balances')).toBeVisible()
      await expect(
        page.locator('[data-testid="math-transfer-annotation"]').first()
      ).toContainText(/Clears .+'s balance · .+ now even/)

      // Confirm settlement.
      await page.getByRole('button', { name: /Confirm/ }).click()
      await expect(page.getByText(/Settled by/)).toBeVisible()

      // Expand the locked-card math; same derivation style.
      const lockedToggle = page
        .locator('[data-testid^="settlement-math-toggle-"]')
        .first()
      await lockedToggle.click()
      await expect(page.getByText('Net balances')).toBeVisible()
      await expect(
        page.locator('[data-testid="math-transfer-annotation"]').first()
      ).toContainText(/Clears .+'s balance · .+ now even/)

      await bobContext.dispose()
    })
  })

  // -------------------------------------------------------------------
  // Mixed expense types: overlap, partial overlap, and explicit participants
  // -------------------------------------------------------------------
  // Event: a 7-day window (days 1–7). Three users with different attendance:
  //   Alice (creator): full trip (days 1–7)
  //   Bob:             partial (days 1–4)
  //   Carol:           partial (days 3–7)
  //
  // Expenses:
  //   1. Alice pays €70 groceries, days 1–7, everyone (RSVP overlap split)
  //      Overlap days: Alice 7, Bob 4, Carol 5 → total 16
  //      Shares: Alice 70*7/16=30.625, Bob 70*4/16=17.50, Carol 70*5/16=21.875
  //   2. Bob pays €30 taxi, day 2 only, everyone (overlap split — only Alice+Bob present)
  //      Overlap: Alice 1 day, Bob 1 day, Carol 0 → shares: 15 each
  //   3. Alice pays €45 dinner, specific people: [Bob, Carol] (equal split)
  //      Shares: Bob 22.50, Carol 22.50
  //
  // Totals:
  //   Alice: share 30.63+15=45.63, paid 70+45=115 → balance -69.38 (owed)
  //   Bob:   share 17.50+15+22.50=55.00, paid 30 → balance +25.00 (owes)
  //   Carol: share 21.88+0+22.50=44.38, paid 0 → balance +44.38 (owes)
  //
  // Transfers: Bob→Alice ~25, Carol→Alice ~44.38
  test.describe('Mixed Expense Settlement', () => {
    test('settles mixed expense types correctly: overlap, partial, and participants', async ({
      playwright,
    }) => {
      const aliceContext = await newApiContext(playwright)
      const { token: aliceToken, userId: aliceId } = await getTestSession(
        aliceContext,
        'e2e-mixed-settle-alice@example.com',
        'Mixed Alice'
      )

      const { eventId } = await createResolvedEvent(
        aliceContext,
        'Mixed Expense Settlement'
      )

      const workspaceId = await getWorkspaceId(aliceContext)

      // Create Bob and Carol, add to workspace, RSVP with partial dates
      const bobContext = await newApiContext(playwright)
      const { userId: bobId } = await getTestSession(
        bobContext,
        'e2e-mixed-settle-bob@example.com',
        'Mixed Bob'
      )
      await addMemberToWorkspace(
        aliceContext,
        workspaceId,
        'e2e-mixed-settle-bob@example.com'
      )
      await bobContext.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: {
          attending: true,
          start_date: offsetDate(14),
          end_date: offsetDate(17),
        },
      })

      const carolContext = await newApiContext(playwright)
      const { userId: carolId } = await getTestSession(
        carolContext,
        'e2e-mixed-settle-carol@example.com',
        'Mixed Carol'
      )
      await addMemberToWorkspace(
        aliceContext,
        workspaceId,
        'e2e-mixed-settle-carol@example.com'
      )
      await carolContext.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: {
          attending: true,
          start_date: offsetDate(16),
          end_date: offsetDate(20),
        },
      })

      // Expense 1: Alice pays €70 groceries for everyone (RSVP overlap)
      await aliceContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Groceries',
          amount: 70,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })

      // Expense 2: Bob pays €30 taxi on day 2 for everyone (only Alice+Bob overlap)
      await bobContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Taxi',
          amount: 30,
          start_date: offsetDate(15),
          end_date: offsetDate(15),
        },
      })

      // Expense 3: Alice pays €45 dinner for specific people (Bob and Carol)
      const dinnerResp = await aliceContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Dinner',
          amount: 45,
          start_date: offsetDate(16),
          end_date: offsetDate(16),
          participant_ids: [bobId, carolId],
        },
      })
      expect(dinnerResp.status()).toBe(201)

      // Verify the dinner expense has participants
      const dinnerBody = await dinnerResp.json()
      const dinnerExpense = getObjectByType(dinnerBody.objects, 'expense')
      expect(dinnerExpense!.participantIds.length).toBe(2)

      // Settle
      const settleResp = await aliceContext.post(
        `${API_BASE}/api/settlements`,
        {
          data: { event_id: eventId },
        }
      )
      expect(settleResp.status()).toBe(201)
      const settleBody = await settleResp.json()

      const transfers = getObjectsByType(
        settleBody.objects,
        'settlementTransfer'
      )
      expect(transfers.length).toBe(2)

      // Both transfers should go to Alice (she's owed money)
      for (const t of transfers) {
        expect(t.toUserId).toBe(aliceId)
      }

      // Find Bob's and Carol's transfers
      const bobTransfer = transfers.find((t) => t.fromUserId === bobId)
      const carolTransfer = transfers.find((t) => t.fromUserId === carolId)
      expect(bobTransfer).toBeDefined()
      expect(carolTransfer).toBeDefined()

      // Bob: share ≈ 55.00, paid 30 → owes ≈ 25.00
      expect(bobTransfer!.amount).toBeCloseTo(25.0, 1)
      // Carol: share ≈ 44.38, paid 0 → owes ≈ 44.38
      expect(carolTransfer!.amount).toBeCloseTo(44.38, 1)

      // Total transferred should equal Alice's net (what she's owed)
      const totalTransferred = transfers.reduce(
        (sum: number, t: { amount: number }) => sum + t.amount,
        0
      )
      // Alice paid 115, share ≈ 45.63 → owed ≈ 69.38
      expect(totalTransferred).toBeCloseTo(69.38, 1)

      // All expenses should now be marked as settled
      const expenses = getObjectsByType(settleBody.objects, 'expense')
      for (const e of expenses) {
        expect(e.settlementId).toBe(
          settleBody.objects.find(
            (o: { objectType: string }) => o.objectType === 'settlement'
          )!.id
        )
      }

      await bobContext.dispose()
      await carolContext.dispose()
      await aliceContext.dispose()
    })
  })

  test.describe('Chain: settle, revert, new expense, top-up', () => {
    test('net transfers across the chain reconcile with the real fair share', async ({
      playwright,
    }) => {
      const aliceContext = await newApiContext(playwright)
      const { userId: aliceId } = await getTestSession(
        aliceContext,
        'e2e-chain-alice@example.com',
        'Chain Alice'
      )
      const { eventId } = await createResolvedEvent(
        aliceContext,
        'Chain Settlement Flow'
      )
      const workspaceId = await getWorkspaceId(aliceContext)

      const bobContext = await newApiContext(playwright)
      const { userId: bobId } = await getTestSession(
        bobContext,
        'e2e-chain-bob@example.com',
        'Chain Bob'
      )
      await addMemberToWorkspace(
        aliceContext,
        workspaceId,
        'e2e-chain-bob@example.com'
      )
      await bobContext.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: { attending: true },
      })

      const carolContext = await newApiContext(playwright)
      const { userId: carolId } = await getTestSession(
        carolContext,
        'e2e-chain-carol@example.com',
        'Chain Carol'
      )
      await addMemberToWorkspace(
        aliceContext,
        workspaceId,
        'e2e-chain-carol@example.com'
      )
      await carolContext.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: { attending: true },
      })

      // Alice pays 90; RSVP-overlap split between A/B/C = 30 each.
      const firstResp = await aliceContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Groceries',
          amount: 90,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })
      const firstExpenseId = getObjectByType(
        (await firstResp.json()).objects,
        'expense'
      )!.id

      // Settlement 1: B→A 30, C→A 30.
      const settle1 = await aliceContext.post(`${API_BASE}/api/settlements`, {
        data: { event_id: eventId },
      })
      expect(settle1.status()).toBe(201)
      const transfers1 = getObjectsByType(
        (await settle1.json()).objects,
        'settlementTransfer'
      ) as Array<{
        id: string
        fromUserId: string
        toUserId: string
        amount: number
        supersededAt: string | null
      }>
      expect(transfers1.length).toBe(2)
      for (const t of transfers1) expect(t.toUserId).toBe(aliceId)
      const bobToAlice = transfers1.find((t) => t.fromUserId === bobId)!
      const carolToAlice = transfers1.find((t) => t.fromUserId === carolId)!
      expect(bobToAlice.amount).toBeCloseTo(30, 2)
      expect(carolToAlice.amount).toBeCloseTo(30, 2)

      // Alice reverts her groceries expense — the real-world purchase turned
      // out not to be a shared one.
      const revertResp = await aliceContext.post(
        `${API_BASE}/api/expenses/${firstExpenseId}/revert`
      )
      expect(revertResp.status()).toBe(201)

      // Bob pays 60 for a new shared expense afterwards; split 20 each.
      await bobContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Dinner',
          amount: 60,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })

      // Top-up: carries the revert delta plus the new expense.
      const settle2 = await aliceContext.post(`${API_BASE}/api/settlements`, {
        data: { event_id: eventId },
      })
      expect(settle2.status()).toBe(201)
      const settle2Body = await settle2.json()
      const topUp = getObjectByType(settle2Body.objects, 'settlement') as {
        previousSettlementId: string | null
      }
      expect(topUp.previousSettlementId).not.toBeNull()

      // Re-fetch both settlements' transfers so superseded_at reflects the
      // state *after* the top-up. The settle1 response captured transfers1
      // before they were superseded, so the cached supersededAt on those is
      // null — not useful for the filter below.
      const settlementsResp = await aliceContext.get(
        `${API_BASE}/api/settlements?event_id=${eventId}`
      )
      const activeTransfers = (
        getObjectsByType(
          (await settlementsResp.json()).objects,
          'settlementTransfer'
        ) as Array<{
          fromUserId: string
          toUserId: string
          amount: number
          supersededAt: string | null
        }>
      ).filter((t) => !t.supersededAt)

      // Per-user net movement across the active (non-superseded) transfers.
      // Only the €60 dinner survives on the ledger (Alice's 90 was reverted),
      // split 20 each: Alice owes 20, Bob is owed 40, Carol owes 20.
      const net: Record<string, number> = {
        [aliceId]: 0,
        [bobId]: 0,
        [carolId]: 0,
      }
      for (const t of activeTransfers) {
        net[t.fromUserId] = (net[t.fromUserId] ?? 0) + t.amount
        net[t.toUserId] = (net[t.toUserId] ?? 0) - t.amount
      }

      expect(net[aliceId]).toBeCloseTo(20, 2)
      expect(net[bobId]).toBeCloseTo(-40, 2)
      expect(net[carolId]).toBeCloseTo(20, 2)

      // Sum of signed net movements must be zero — money conserves.
      const sum = Object.values(net).reduce((a, b) => a + b, 0)
      expect(Math.abs(sum)).toBeLessThan(0.01)

      // Sanity: the revert expense is linked to the original.
      const allExpensesResp = await aliceContext.get(
        `${API_BASE}/api/expenses?event_id=${eventId}`
      )
      const allExpenses = getObjectsByType(
        (await allExpensesResp.json()).objects,
        'expense'
      ) as Array<{
        id: string
        amount: number
        revertsExpenseId: string | null
      }>
      const revertRow = allExpenses.find(
        (e) => e.revertsExpenseId === firstExpenseId
      )
      expect(revertRow).toBeDefined()
      expect(revertRow!.amount).toBeCloseTo(-90, 2)

      await bobContext.dispose()
      await carolContext.dispose()
      await aliceContext.dispose()
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
