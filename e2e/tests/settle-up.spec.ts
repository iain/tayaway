import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getObjectsByType,
  getTestSession,
  setupAuthenticatedPage,
  createResolvedEvent,
  addMemberToWorkspace,
  getWorkspaceId,
  newApiContext,
} from '../helpers'

// Resolved events use date range 2026-06-01 to 2026-06-07
const DEFAULT_START = '2026-06-01'
const DEFAULT_END = '2026-06-07'

// Builds a fully-settled event between Alice and Bob for a single expense
// paid by `payer`. Returns the per-event transfer ids so the caller can
// assert on them after the workspace-level mark-paid runs.
async function settleSingleExpenseEvent(opts: {
  alice: APIRequestContext
  bob: APIRequestContext
  workspaceId: string
  bobEmail: string
  name: string
  amount: number
  payer: 'alice' | 'bob'
}): Promise<{ eventId: string; transferIds: string[] }> {
  const { eventId } = await createResolvedEvent(opts.alice, opts.name)
  await addMemberToWorkspace(opts.alice, opts.workspaceId, opts.bobEmail)
  await opts.bob.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
    data: { attending: true },
  })

  const payerCtx = opts.payer === 'alice' ? opts.alice : opts.bob
  await payerCtx.post(`${API_BASE}/api/expenses`, {
    data: {
      event_id: eventId,
      description: opts.name,
      amount: opts.amount,
      start_date: DEFAULT_START,
      end_date: DEFAULT_END,
    },
  })

  const settleResp = await opts.alice.post(`${API_BASE}/api/settlements`, {
    data: { event_id: eventId },
  })
  expect(settleResp.status()).toBe(201)
  const transfers = getObjectsByType(
    (await settleResp.json()).objects,
    'settlementTransfer'
  )
  return { eventId, transferIds: transfers.map((t) => t.id) }
}

test.describe('Workspace Settle Up — multi-event netting', () => {
  // Two events with offsetting transfers between the same pair: Alice paid
  // €80 for both attendees on event 1 (Bob owes Alice €40); Bob paid €30 on
  // event 2 (Alice owes Bob €15). Alice's perspective: net Bob owes her €25.
  test('nets two opposite-direction transfers and marks both paid in one click', async ({
    browser,
    playwright,
  }) => {
    const aliceContext = await newApiContext(playwright)
    const { token: aliceToken } = await getTestSession(
      aliceContext,
      `e2e-net-alice-${Date.now()}@example.com`,
      'Net Alice'
    )
    const workspaceId = await getWorkspaceId(aliceContext)

    const bobEmail = `e2e-net-bob-${Date.now()}@example.com`
    const bobContext = await newApiContext(playwright)
    await getTestSession(bobContext, bobEmail, 'Net Bob')

    const event1 = await settleSingleExpenseEvent({
      alice: aliceContext,
      bob: bobContext,
      workspaceId,
      bobEmail,
      name: 'Cabin trip',
      amount: 80,
      payer: 'alice',
    })
    const event2 = await settleSingleExpenseEvent({
      alice: aliceContext,
      bob: bobContext,
      workspaceId,
      bobEmail,
      name: 'Bowling night',
      amount: 30,
      payer: 'bob',
    })

    // Sanity-check the API state before driving the UI: each event has one
    // transfer in opposite directions between Alice and Bob.
    const allTransferIds = [...event1.transferIds, ...event2.transferIds]
    expect(allTransferIds.length).toBe(2)

    // Visit /settle-up as Alice — the net recipient.
    const aliceBrowserCtx = await browser.newContext()
    const page = await aliceBrowserCtx.newPage()
    await setupAuthenticatedPage(page, aliceToken)
    await page.goto('/settle-up')
    await expect(page.getByTestId('page-title')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Owed-to-you section should show one card for €25 from Bob.
    const owedSection = page.getByRole('heading', { name: 'Owed to you' })
    await expect(owedSection).toBeVisible()
    const card = page.locator('li').filter({ hasText: 'Net Bob' }).first()
    await expect(card).toBeVisible()
    await expect(card).toContainText('€25.00')

    // Expand the breakdown — both events should appear with their per-event
    // amounts and opposite-direction signs.
    await card.getByRole('button', { name: /transfer/ }).click()
    await expect(card).toContainText('Cabin trip')
    await expect(card).toContainText('Bowling night')
    await expect(card).toContainText('+€40.00')
    await expect(card).toContainText('−€15.00')

    // Click Mark as paid; backend will mark both underlying transfers paid.
    const [markResp] = await Promise.all([
      page.waitForResponse(
        (resp) =>
          resp.url().includes('/api/settlements/net-transfers/mark-paid') &&
          resp.request().method() === 'PUT'
      ),
      card.getByRole('button', { name: 'Mark as paid' }).click(),
    ])
    expect(markResp.ok()).toBeTruthy()

    // Card disappears from the page once both underlying transfers are paid.
    await expect(card).not.toBeVisible()
    await expect(page.getByTestId('settle-up-empty')).toBeVisible()

    // Verify both per-event transfers are marked paid via the API.
    for (const tid of allTransferIds) {
      const eid = event1.transferIds.includes(tid)
        ? event1.eventId
        : event2.eventId
      const resp = await aliceContext.get(
        `${API_BASE}/api/settlements?event_id=${eid}`
      )
      const transfers = getObjectsByType(
        (await resp.json()).objects,
        'settlementTransfer'
      )
      const transfer = transfers.find((t) => t.id === tid)
      expect(transfer, `transfer ${tid} should still exist`).toBeDefined()
      expect(transfer!.paidAt, `transfer ${tid} paidAt`).not.toBeNull()
    }

    await page.close()
    await aliceBrowserCtx.close()
    await bobContext.dispose()
    await aliceContext.dispose()
  })

  test("rejects mark-paid when the live net no longer matches the user's expectation", async ({
    playwright,
  }) => {
    // API-level coverage for drift detection — Alice has €40 owed to her,
    // sends a stale €12.34 from a previous render, gets 409. Then the
    // correct amount succeeds, proving the endpoint is otherwise fine.
    const aliceContext = await newApiContext(playwright)
    await getTestSession(
      aliceContext,
      `e2e-net-drift-alice-${Date.now()}@example.com`,
      'Drift Alice'
    )
    const workspaceId = await getWorkspaceId(aliceContext)

    const bobEmail = `e2e-net-drift-bob-${Date.now()}@example.com`
    const bobContext = await newApiContext(playwright)
    const { userId: bobId } = await getTestSession(
      bobContext,
      bobEmail,
      'Drift Bob'
    )

    await settleSingleExpenseEvent({
      alice: aliceContext,
      bob: bobContext,
      workspaceId,
      bobEmail,
      name: 'Drift event',
      amount: 80,
      payer: 'alice',
    })

    const driftResp = await aliceContext.put(
      `${API_BASE}/api/settlements/net-transfers/mark-paid?workspace_id=${workspaceId}`,
      { data: { counterparty: bobId, expected_amount: 12.34 } }
    )
    expect(driftResp.status()).toBe(409)
    expect((await driftResp.json()).error).toMatch(/Balance has changed/i)

    const okResp = await aliceContext.put(
      `${API_BASE}/api/settlements/net-transfers/mark-paid?workspace_id=${workspaceId}`,
      { data: { counterparty: bobId, expected_amount: 40 } }
    )
    expect(okResp.ok()).toBeTruthy()

    await bobContext.dispose()
    await aliceContext.dispose()
  })

  test('rejects mark-paid when the caller is the net sender, not the recipient', async ({
    playwright,
  }) => {
    const aliceContext = await newApiContext(playwright)
    const { userId: aliceId } = await getTestSession(
      aliceContext,
      `e2e-net-auth-alice-${Date.now()}@example.com`,
      'Auth Alice'
    )
    const workspaceId = await getWorkspaceId(aliceContext)

    const bobEmail = `e2e-net-auth-bob-${Date.now()}@example.com`
    const bobContext = await newApiContext(playwright)
    await getTestSession(bobContext, bobEmail, 'Auth Bob')

    await settleSingleExpenseEvent({
      alice: aliceContext,
      bob: bobContext,
      workspaceId,
      bobEmail,
      name: 'Auth check event',
      amount: 80,
      payer: 'alice',
    })

    // Bob is the net sender (he owes Alice €40). Marking paid from his side
    // should be rejected — only the recipient may do that.
    const resp = await bobContext.put(
      `${API_BASE}/api/settlements/net-transfers/mark-paid?workspace_id=${workspaceId}`,
      { data: { counterparty: aliceId, expected_amount: 40 } }
    )
    expect(resp.status()).toBe(403)
    expect((await resp.json()).error).toBe('not_recipient')

    await bobContext.dispose()
    await aliceContext.dispose()
  })
})
