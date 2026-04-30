import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getObjectByType,
  getObjectsByType,
  getTestSession,
  setupAuthenticatedPage,
  createBareEvent,
  createResolvedEvent,
  addMemberToWorkspace,
  getWorkspaceId,
  PAGE_LOAD_TIMEOUT,
  newApiContext,
} from '../helpers'

const TEST_EMAIL = 'e2e-expenses@example.com'
const TEST_NAME = 'E2E Expenses User'

// Resolved events use date range 2026-06-01 to 2026-06-07
const DEFAULT_START = '2026-06-01'
const DEFAULT_END = '2026-06-07'

test.describe('Expenses Feature', () => {
  test.describe('Expenses API - Unauthenticated', () => {
    test('all expense endpoints require auth', async ({ request }) => {
      const fakeId = '00000000-0000-0000-0000-000000000000'
      const responses = await Promise.all([
        request.get(`${API_BASE}/api/expenses?event_id=${fakeId}`),
        request.post(`${API_BASE}/api/expenses`, {
          data: {
            event_id: fakeId,
            description: 'Dinner',
            amount: 50,
            start_date: DEFAULT_START,
            end_date: DEFAULT_END,
          },
        }),
        request.put(`${API_BASE}/api/expenses/${fakeId}`, {
          data: { description: 'Lunch' },
        }),
        request.delete(`${API_BASE}/api/expenses/${fakeId}`),
      ])
      for (const response of responses) {
        expect(response.status()).toBe(401)
        const body = await response.json()
        expect(body.error).toBe('Authorization required')
      }
    })
  })

  test.describe('Expenses API - Authenticated', () => {
    let apiContext: APIRequestContext
    let eventId: string

    test.beforeAll(async ({ playwright }) => {
      apiContext = await newApiContext(playwright)
      await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      ;({ eventId } = await createResolvedEvent(
        apiContext,
        'Expense API Test Event'
      ))
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('GET /api/expenses requires event_id', async () => {
      const response = await apiContext.get(`${API_BASE}/api/expenses`)
      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBeTruthy()
    })

    test('GET /api/expenses returns 403 for non-member event', async () => {
      const fakeId = '00000000-0000-0000-0000-000000000000'
      const response = await apiContext.get(
        `${API_BASE}/api/expenses?event_id=${fakeId}`
      )
      expect(response.status()).toBe(403)
    })

    test('GET /api/expenses returns empty list for event with no expenses', async () => {
      const response = await apiContext.get(
        `${API_BASE}/api/expenses?event_id=${eventId}`
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body).toHaveProperty('objects')
      expect(Array.isArray(body.objects)).toBeTruthy()
      const expenses = getObjectsByType(body.objects, 'expense')
      expect(expenses).toHaveLength(0)
    })

    test('POST /api/expenses requires description', async () => {
      const response = await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          amount: 10,
          start_date: '2026-01-01',
          end_date: '2026-01-02',
        },
      })
      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBeTruthy()
    })

    test('POST /api/expenses requires positive amount', async () => {
      const responses = await Promise.all([
        apiContext.post(`${API_BASE}/api/expenses`, {
          data: {
            event_id: eventId,
            description: 'Dinner',
            start_date: '2026-01-01',
            end_date: '2026-01-02',
          },
        }),
        apiContext.post(`${API_BASE}/api/expenses`, {
          data: {
            event_id: eventId,
            description: 'Dinner',
            amount: 0,
            start_date: '2026-01-01',
            end_date: '2026-01-02',
          },
        }),
        apiContext.post(`${API_BASE}/api/expenses`, {
          data: {
            event_id: eventId,
            description: 'Dinner',
            amount: -5,
            start_date: '2026-01-01',
            end_date: '2026-01-02',
          },
        }),
      ])
      for (const response of responses) {
        expect(response.status()).toBe(400)
      }
    })

    test('POST /api/expenses requires dates', async () => {
      const response = await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Dinner',
          amount: 10,
        },
      })
      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toContain('date')
    })

    test('full expense CRUD lifecycle', async () => {
      // Create
      const createResponse = await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Team dinner',
          amount: 120.5,
          start_date: '2026-06-02',
          end_date: '2026-06-04',
        },
      })
      expect(createResponse.status()).toBe(201)
      const createBody = await createResponse.json()
      const created = getObjectByType(createBody.objects, 'expense')
      expect(created).toHaveProperty('id')
      expect(created?.description).toBe('Team dinner')
      expect(created?.amount).toBeCloseTo(120.5)
      expect(created).toHaveProperty('eventId', eventId)
      expect(created).toHaveProperty('startDate', '2026-06-02')
      expect(created).toHaveProperty('endDate', '2026-06-04')
      const expenseId = created!.id

      // Read — appears in event GET
      const getResponse = await apiContext.get(
        `${API_BASE}/api/expenses?event_id=${eventId}`
      )
      expect(getResponse.ok()).toBeTruthy()
      const getBody = await getResponse.json()
      const listed = getObjectsByType(getBody.objects, 'expense')
      expect(listed.some((e) => e.id === expenseId)).toBeTruthy()

      // Update description
      const updateResponse = await apiContext.put(
        `${API_BASE}/api/expenses/${expenseId}`,
        { data: { description: 'Team lunch' } }
      )
      expect(updateResponse.ok()).toBeTruthy()
      const updateBody = await updateResponse.json()
      const updated = getObjectByType(updateBody.objects, 'expense')
      expect(updated?.description).toBe('Team lunch')

      // Update amount
      const updateAmountResponse = await apiContext.put(
        `${API_BASE}/api/expenses/${expenseId}`,
        { data: { amount: 85.0 } }
      )
      expect(updateAmountResponse.ok()).toBeTruthy()
      const updateAmountBody = await updateAmountResponse.json()
      const updatedAmount = getObjectByType(updateAmountBody.objects, 'expense')
      expect(updatedAmount?.amount).toBeCloseTo(85.0)

      // Update dates
      const updateDatesResponse = await apiContext.put(
        `${API_BASE}/api/expenses/${expenseId}`,
        { data: { start_date: '2026-06-03', end_date: '2026-06-05' } }
      )
      expect(updateDatesResponse.ok()).toBeTruthy()
      const updateDatesBody = await updateDatesResponse.json()
      const updatedDates = getObjectByType(updateDatesBody.objects, 'expense')
      expect(updatedDates).toHaveProperty('startDate', '2026-06-03')
      expect(updatedDates).toHaveProperty('endDate', '2026-06-05')

      // Delete
      const deleteResponse = await apiContext.delete(
        `${API_BASE}/api/expenses/${expenseId}`
      )
      expect(deleteResponse.ok()).toBeTruthy()
      const deleteBody = await deleteResponse.json()
      expect(deleteBody.deleted).toHaveLength(1)
      expect(deleteBody.deleted[0].objectType).toBe('expense')
      expect(deleteBody.deleted[0].id).toBe(expenseId)

      // Verify deleted — 410 Gone
      const verifyResponse = await apiContext.put(
        `${API_BASE}/api/expenses/${expenseId}`,
        { data: { description: 'Ghost' } }
      )
      expect(verifyResponse.status()).toBe(410)
    })

    test('idempotent create with client-provided id', async () => {
      const id = crypto.randomUUID()

      const first = await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Hotel',
          amount: 200,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
          id,
        },
      })
      expect(first.status()).toBe(201)

      const second = await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Hotel',
          amount: 200,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
          id,
        },
      })
      expect(second.status()).toBe(201)
      const secondBody = await second.json()
      const returned = getObjectByType(secondBody.objects, 'expense')
      expect(returned?.id).toBe(id)
    })

    test('expense dates must fall within event date range', async () => {
      // Create a resolved event with dates 2026-06-01 to 2026-06-07
      const { eventId: resolvedEventId } = await createResolvedEvent(
        apiContext,
        'Date Validation Event'
      )

      // Expense before event start
      const beforeResp = await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: resolvedEventId,
          description: 'Too early',
          amount: 10,
          start_date: '2026-05-30',
          end_date: '2026-06-02',
        },
      })
      expect(beforeResp.status()).toBe(400)

      // Expense after event end
      const afterResp = await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: resolvedEventId,
          description: 'Too late',
          amount: 10,
          start_date: '2026-06-05',
          end_date: '2026-06-10',
        },
      })
      expect(afterResp.status()).toBe(400)

      // Expense within event range — should succeed
      const withinResp = await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: resolvedEventId,
          description: 'Just right',
          amount: 10,
          start_date: '2026-06-02',
          end_date: '2026-06-05',
        },
      })
      expect(withinResp.status()).toBe(201)
    })
  })

  test.describe('Expenses - on-behalf-of enforcement', () => {
    let ownerContext: APIRequestContext
    let otherContext: APIRequestContext
    let eventId: string
    let expenseId: string

    test.beforeAll(async ({ playwright }) => {
      ownerContext = await newApiContext(playwright)
      await getTestSession(ownerContext, TEST_EMAIL, TEST_NAME)
      ;({ eventId } = await createResolvedEvent(
        ownerContext,
        'Auth Test Event'
      ))

      // Create a second user and add them to the same workspace
      otherContext = await newApiContext(playwright)
      await getTestSession(
        otherContext,
        'e2e-expenses-other@example.com',
        'Other E2E User'
      )

      const wsResp = await ownerContext.get(`${API_BASE}/api/workspaces`)
      const wsBody = await wsResp.json()
      const workspace = getObjectByType(wsBody.objects, 'workspace')!

      await addMemberToWorkspace(
        ownerContext,
        workspace.id,
        'e2e-expenses-other@example.com'
      )
    })

    // Each test gets its own fresh expense so update/delete tests don't
    // step on each other regardless of execution order.
    test.beforeEach(async () => {
      const resp = await ownerContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Taxi',
          amount: 30,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })
      const body = await resp.json()
      expenseId = getObjectByType(body.objects, 'expense')!.id
    })

    test.afterAll(async () => {
      await ownerContext.dispose()
      await otherContext.dispose()
    })

    test('another workspace member can update an expense on the owner behalf', async () => {
      const response = await otherContext.put(
        `${API_BASE}/api/expenses/${expenseId}`,
        { data: { description: 'Corrected by other' } }
      )
      expect(response.ok()).toBeTruthy()
    })

    test('another workspace member can delete an expense on the owner behalf', async () => {
      const response = await otherContext.delete(
        `${API_BASE}/api/expenses/${expenseId}`
      )
      expect(response.ok()).toBeTruthy()
    })

    test('creator can update their own expense', async () => {
      const response = await ownerContext.put(
        `${API_BASE}/api/expenses/${expenseId}`,
        { data: { description: 'Updated Taxi' } }
      )
      expect(response.ok()).toBeTruthy()
    })
  })

  test.describe('Expense Split UI', () => {
    const SPLIT_USER_A_EMAIL = 'e2e-split-a@example.com'
    const SPLIT_USER_A_NAME = 'Split User A'
    const SPLIT_USER_B_EMAIL = 'e2e-split-b@example.com'
    const SPLIT_USER_B_NAME = 'Split User B'

    test('cost split section is hidden when event has no dates', async ({
      page,
      playwright,
    }) => {
      const apiContext = await newApiContext(playwright)
      const { token } = await getTestSession(
        apiContext,
        SPLIT_USER_A_EMAIL,
        SPLIT_USER_A_NAME
      )
      const eventId = await createBareEvent(apiContext, 'No Dates Split Test')
      await apiContext.dispose()

      await setupAuthenticatedPage(page, token)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(
        page.getByRole('heading', { name: 'Expenses', exact: true })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
      await expect(
        page.getByRole('heading', { name: 'Fair shares' })
      ).not.toBeVisible()
    })

    test('shows split for single attendee with settled balance', async ({
      page,
      playwright,
    }) => {
      const apiContext = await newApiContext(playwright)
      const { token } = await getTestSession(
        apiContext,
        SPLIT_USER_A_EMAIL,
        SPLIT_USER_A_NAME
      )
      const { eventId } = await createResolvedEvent(apiContext)

      await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Hotel',
          amount: 40,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })
      await apiContext.dispose()

      await setupAuthenticatedPage(page, token)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(
        page.getByRole('heading', { name: 'Fair shares' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Single attendee is even (they paid exactly their share)
      await expect(
        page.getByTestId('cost-split-table').getByText('even', { exact: true })
      ).toBeVisible()
    })

    test('shows correct per-person balances with two attendees', async ({
      page,
      playwright,
    }) => {
      // User A creates event and is auto-RSVP'd attending after poll close
      const apiContextA = await newApiContext(playwright)
      const { token: tokenA } = await getTestSession(
        apiContextA,
        SPLIT_USER_A_EMAIL,
        SPLIT_USER_A_NAME
      )
      const { eventId } = await createResolvedEvent(apiContextA)

      // Add User B to the workspace and have them RSVP attending
      const apiContextB = await newApiContext(playwright)
      await getTestSession(apiContextB, SPLIT_USER_B_EMAIL, SPLIT_USER_B_NAME)

      const wsResp = await apiContextA.get(`${API_BASE}/api/workspaces`)
      const wsBody = await wsResp.json()
      const workspace = getObjectByType(wsBody.objects, 'workspace')!

      await addMemberToWorkspace(apiContextA, workspace.id, SPLIT_USER_B_EMAIL)

      await apiContextB.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: { attending: true },
      })

      // User A pays €100 — both attend 6 nights, expense covers full event
      await apiContextA.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Hotel',
          amount: 100,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })

      await apiContextA.dispose()
      await apiContextB.dispose()

      await setupAuthenticatedPage(page, tokenA)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(
        page.getByRole('heading', { name: 'Fair shares' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // User A: paid €100, fair share €50.00 → is owed €50.00 back
      const splitTable = page.getByTestId('cost-split-table')
      const rowA = splitTable
        .getByRole('row')
        .filter({ hasText: SPLIT_USER_A_NAME })
      await expect(rowA.getByText('€100.00', { exact: true })).toBeVisible()
      await expect(rowA.getByText('€50.00', { exact: true })).toBeVisible()
      await expect(rowA.getByText('is owed €50.00')).toBeVisible()

      // User B: paid €0.00, fair share €50.00 → owes €50.00
      const rowB = splitTable
        .getByRole('row')
        .filter({ hasText: SPLIT_USER_B_NAME })
      await expect(rowB.getByText('€0.00', { exact: true })).toBeVisible()
      await expect(rowB.getByText('€50.00', { exact: true })).toBeVisible()
      await expect(rowB.getByText('owes €50.00')).toBeVisible()
    })

    test('weights the split by per-participant factors', async ({
      page,
      playwright,
    }) => {
      const apiContextA = await newApiContext(playwright)
      const { token: tokenA, userId: userAId } = await getTestSession(
        apiContextA,
        SPLIT_USER_A_EMAIL,
        SPLIT_USER_A_NAME
      )
      const { eventId } = await createResolvedEvent(apiContextA, 'Factor Split')

      const apiContextB = await newApiContext(playwright)
      const { userId: userBId } = await getTestSession(
        apiContextB,
        SPLIT_USER_B_EMAIL,
        SPLIT_USER_B_NAME
      )

      const wsResp = await apiContextA.get(`${API_BASE}/api/workspaces`)
      const wsBody = await wsResp.json()
      const workspace = getObjectByType(wsBody.objects, 'workspace')!
      await addMemberToWorkspace(apiContextA, workspace.id, SPLIT_USER_B_EMAIL)

      await apiContextB.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: { attending: true },
      })

      // A pays €30. Split specifically among A (factor 1) and B (factor 2):
      // total factor 3 → A owes €10.00, B owes €20.00.
      await apiContextA.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Dinner',
          amount: 30,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
          participants: [
            { user_id: userAId, factor: 1 },
            { user_id: userBId, factor: 2 },
          ],
        },
      })

      await apiContextA.dispose()
      await apiContextB.dispose()

      await setupAuthenticatedPage(page, tokenA)
      await page.goto(`/events/${eventId}/expenses`)
      await expect(
        page.getByRole('heading', { name: 'Fair shares' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      const splitTable = page.getByTestId('cost-split-table')
      const rowA = splitTable
        .getByRole('row')
        .filter({ hasText: SPLIT_USER_A_NAME })
      // A paid €30, fair share €10.00 → is owed €20.00 back
      await expect(rowA.getByText('€30.00', { exact: true })).toBeVisible()
      await expect(rowA.getByText('€10.00', { exact: true })).toBeVisible()
      await expect(rowA.getByText('is owed €20.00')).toBeVisible()

      const rowB = splitTable
        .getByRole('row')
        .filter({ hasText: SPLIT_USER_B_NAME })
      // B paid nothing, fair share €20.00 → owes €20.00
      await expect(rowB.getByText('€0.00', { exact: true })).toBeVisible()
      await expect(rowB.getByText('€20.00', { exact: true })).toBeVisible()
      await expect(rowB.getByText('owes €20.00')).toBeVisible()
    })

    test('date-scoped expense only splits among overlapping attendees', async ({
      page,
      playwright,
    }) => {
      // User A creates event, both attend, but User B only attends partial dates
      const apiContextA = await newApiContext(playwright)
      const { token: tokenA } = await getTestSession(
        apiContextA,
        SPLIT_USER_A_EMAIL,
        SPLIT_USER_A_NAME
      )
      const { eventId } = await createResolvedEvent(
        apiContextA,
        'Date Scoped Split'
      )

      const apiContextB = await newApiContext(playwright)
      await getTestSession(apiContextB, SPLIT_USER_B_EMAIL, SPLIT_USER_B_NAME)

      const wsResp = await apiContextA.get(`${API_BASE}/api/workspaces`)
      const wsBody = await wsResp.json()
      const workspace = getObjectByType(wsBody.objects, 'workspace')!

      await addMemberToWorkspace(apiContextA, workspace.id, SPLIT_USER_B_EMAIL)

      // User B RSVPs with partial dates: only 2026-06-05 to 2026-06-07
      await apiContextB.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: {
          attending: true,
          start_date: '2026-06-05',
          end_date: '2026-06-07',
        },
      })

      // Expense covering only first 4 days: 2026-06-01 to 2026-06-04
      // User A attends all 4 days, User B attends 0 days of this expense
      // So User A should bear 100% of this expense
      await apiContextA.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Early dinner',
          amount: 60,
          start_date: '2026-06-01',
          end_date: '2026-06-04',
        },
      })

      await apiContextA.dispose()
      await apiContextB.dispose()

      await setupAuthenticatedPage(page, tokenA)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(
        page.getByRole('heading', { name: 'Fair shares' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // User A paid €60, fair share is €60 (100%) → even
      const splitTable = page.getByTestId('cost-split-table')
      const rowA = splitTable
        .getByRole('row')
        .filter({ hasText: SPLIT_USER_A_NAME })
      await expect(rowA.getByText('even')).toBeVisible()

      // User B: fair share €0.00, paid €0.00 → even
      const rowB = splitTable
        .getByRole('row')
        .filter({ hasText: SPLIT_USER_B_NAME })
      await expect(rowB.getByText('even')).toBeVisible()
    })

    test('expense row expansion shows payer breakdown', async ({
      page,
      playwright,
    }) => {
      const apiContextA = await newApiContext(playwright)
      const { token: tokenA } = await getTestSession(
        apiContextA,
        SPLIT_USER_A_EMAIL,
        SPLIT_USER_A_NAME
      )
      const { eventId } = await createResolvedEvent(
        apiContextA,
        'Expansion Test'
      )

      await apiContextA.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Groceries',
          amount: 30,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })
      await apiContextA.dispose()

      await setupAuthenticatedPage(page, tokenA)
      await page.goto(`/events/${eventId}/expenses`)

      const row = page
        .getByTestId('expense-row')
        .filter({ hasText: 'Groceries' })
      await expect(row).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Click to expand
      await row.click()

      const detail = page.getByTestId('expense-detail')
      await expect(detail).toBeVisible()
      await expect(detail.getByText(SPLIT_USER_A_NAME)).toBeVisible()
      await expect(detail.getByText('€30.00')).toBeVisible()
    })
  })

  test.describe('RSVP required dialog', () => {
    test('shows RSVP required dialog when non-attending user clicks Add expense', async ({
      page,
      playwright,
    }) => {
      const apiContext = await newApiContext(playwright)
      const { token } = await getTestSession(
        apiContext,
        'e2e-rsvp-dialog@example.com',
        'RSVP Dialog User'
      )
      // createResolvedEvent auto-RSVPs the user as attending; change to not attending
      const { eventId } = await createResolvedEvent(
        apiContext,
        'RSVP Dialog Test'
      )
      await apiContext.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: { attending: false },
      })
      await apiContext.dispose()

      await setupAuthenticatedPage(page, token)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(
        page.getByRole('button', { name: 'Add expense' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
      await page.getByRole('button', { name: 'Add expense' }).click()

      // Dialog should appear with explanation
      await expect(page.getByTestId('rsvp-required-dialog')).toBeVisible()
      await expect(page.getByRole('link', { name: 'Go to RSVP' })).toBeVisible()

      // Link should point to the RSVP page
      await page.getByRole('link', { name: 'Go to RSVP' }).click()
      await expect(page).toHaveURL(`/events/${eventId}/rsvp`)
    })
  })

  test.describe('Expenses UI - Unauthenticated', () => {
    test('expenses page redirects to login when not authenticated', async ({
      page,
    }) => {
      const fakeId = '00000000-0000-0000-0000-000000000000'
      await page.goto(`/events/${fakeId}/expenses`)
      await expect(page).toHaveURL('/login')
    })
  })

  test.describe('Expenses UI - Authenticated', () => {
    let sessionToken: string
    let apiContext: APIRequestContext
    let eventId: string
    const uid = Date.now()

    test.beforeAll(async ({ playwright }) => {
      apiContext = await newApiContext(playwright)
      const { token } = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      sessionToken = token
      ;({ eventId } = await createResolvedEvent(
        apiContext,
        `UI Expense Event ${uid}`
      ))
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('expenses page is reachable from event page', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}`)

      await expect(page.getByRole('link', { name: /expenses/i })).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await page.getByRole('link', { name: /expenses/i }).click()

      await expect(page).toHaveURL(`/events/${eventId}/expenses`)
      await expect(
        page.getByRole('heading', { name: 'Expenses', exact: true })
      ).toBeVisible()
    })

    test('shows empty state and add expense button', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(page.getByText(/no expenses yet/i)).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(
        page.getByRole('button', { name: 'Add expense' })
      ).toBeVisible()
    })

    test('can add an expense and see it in the list', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      const description = `Coffee ${uid}`
      await expect(
        page.getByRole('button', { name: 'Add expense' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
      await page.getByRole('button', { name: 'Add expense' }).click()

      // Step 1: Details
      await expect(page.getByTestId('expense-description-input')).toBeVisible()
      await page.getByTestId('expense-description-input').fill(description)
      await page.getByTestId('expense-amount-input').fill('4.50')
      await page.getByTestId('submit-button').click()

      // Step 2: Date (pre-selected from event dates)
      await page.getByTestId('submit-button').click()

      // Step 3: People (default "Everyone")
      await page.getByTestId('submit-button').click()

      const row = page
        .getByTestId('expense-row')
        .filter({ hasText: description })
      await expect(row).toBeVisible()
      await expect(row.getByText('€4.50')).toBeVisible()
    })

    test('shows running total', async ({ page }) => {
      // Create two expenses via API
      await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Total Item A',
          amount: 10.0,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })
      await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Total Item B',
          amount: 5.5,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      // Total should include all expenses for this event (at least A + B = 15.50)
      await expect(page.getByTestId('expenses-total')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
    })

    test('can edit an expense via the edit button', async ({ page }) => {
      const description = `Edit Me ${uid}`

      // Create expense via API
      await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description,
          amount: 25,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      const row = page
        .getByTestId('expense-row')
        .filter({ hasText: description })
      await expect(row).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Click edit button
      await row.getByTestId('edit-expense').click()

      // Modal should open with pre-filled values
      const descInput = page.getByTestId('expense-description-input')
      await expect(descInput).toBeVisible()
      await expect(descInput).toHaveValue(description)

      // Step 1: Change description and amount
      await descInput.fill(`Updated ${uid}`)
      const amountInput = page.getByTestId('expense-amount-input')
      await amountInput.fill('42.00')
      await page.getByTestId('submit-button').click()

      // Step 2: Change dates via calendar (click start, then end)
      await page.getByTestId('calendar-day-2026-06-03').click()
      await page.getByTestId('calendar-day-2026-06-05').click()
      await page.getByTestId('submit-button').click()

      // Step 3: People (keep default)
      const [updateResponse] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/expenses/') &&
            resp.request().method() === 'PUT'
        ),
        page.getByTestId('submit-button').click(),
      ])
      expect(updateResponse.status()).toBe(200)

      // Updated values should appear in the row
      const updatedRow = page
        .getByTestId('expense-row')
        .filter({ hasText: `Updated ${uid}` })
      await expect(updatedRow).toBeVisible()
      await expect(updatedRow.getByText('€42.00')).toBeVisible()
    })

    test('creator sees delete button; expense is removed on click', async ({
      page,
    }) => {
      const description = `Delete Me ${uid}`

      // Create expense via API
      const resp = await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description,
          amount: 99,
          start_date: DEFAULT_START,
          end_date: DEFAULT_END,
        },
      })
      const body = await resp.json()
      const expense = getObjectByType(body.objects, 'expense')!

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      const row = page
        .getByTestId('expense-row')
        .filter({ hasText: description })
      await expect(row).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Wait for the DELETE request to complete before verifying via API
      const [deleteResponse] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/expenses/') &&
            resp.request().method() === 'DELETE'
        ),
        row.getByTestId('delete-expense').click(),
      ])
      expect(deleteResponse.status()).toBe(200)

      await expect(page.getByText(description)).not.toBeVisible()

      // Verify truly gone via API (should be 410 Gone)
      const verifyResp = await apiContext.delete(
        `${API_BASE}/api/expenses/${expense.id}`
      )
      expect(verifyResp.status()).toBe(410)
    })
  })

  test.describe('Expense Participant Selection', () => {
    const PARTICIPANT_EMAIL = 'e2e-expense-participants@example.com'
    const PARTICIPANT_NAME = 'E2E Expense Participants'
    const SECOND_EMAIL = 'e2e-expense-participants-2@example.com'
    const SECOND_NAME = 'Participant Bob'

    let apiContext: APIRequestContext
    let secondContext: APIRequestContext
    let sessionToken: string
    let eventId: string
    let secondUserId: string

    test.beforeAll(async ({ playwright }) => {
      apiContext = await newApiContext(playwright)
      const { token } = await getTestSession(
        apiContext,
        PARTICIPANT_EMAIL,
        PARTICIPANT_NAME
      )
      sessionToken = token

      // Create event and resolve it
      ;({ eventId } = await createResolvedEvent(
        apiContext,
        'Participant Test Event'
      ))

      // Add a second member and RSVP them
      const workspaceId = await getWorkspaceId(apiContext)
      secondContext = await newApiContext(playwright)
      ;({ userId: secondUserId } = await getTestSession(
        secondContext,
        SECOND_EMAIL,
        SECOND_NAME
      ))
      await addMemberToWorkspace(apiContext, workspaceId, SECOND_EMAIL)

      // RSVP the second user as attending
      await secondContext.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: { attending: true },
      })
    })

    test.afterAll(async () => {
      await apiContext.dispose()
      await secondContext.dispose()
    })

    test('can file an expense on behalf of another attending member', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(
        page.getByRole('button', { name: 'Add expense' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
      await page.getByRole('button', { name: 'Add expense' }).click()

      await expect(page.getByTestId('expense-description-input')).toBeVisible()
      await page
        .getByTestId('expense-description-input')
        .fill('Lunch (filed for Bob)')
      await page.getByTestId('expense-amount-input').fill('17.50')

      // Pick the second user as payer
      await page
        .getByTestId('expense-payer-select')
        .locator('select')
        .selectOption({ label: SECOND_NAME })

      await page.getByTestId('submit-button').click()
      await expect(page.getByTestId('toggle-date-mode')).toBeVisible()
      await page.getByTestId('submit-button').click()
      await expect(page.getByTestId('toggle-people-mode')).toBeVisible()

      const [createResponse] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/expenses') &&
            resp.request().method() === 'POST'
        ),
        page.getByTestId('submit-button').click(),
      ])
      expect(createResponse.status()).toBe(201)

      // Server-side: subject is the second user, filer is the actor
      const expensesResp = await apiContext.get(
        `${API_BASE}/api/expenses?event_id=${eventId}`
      )
      const expensesBody = await expensesResp.json()
      const expense = expensesBody.objects.find(
        (o: {
          objectType: string
          description: string
          userId: string
          createdByUserId: string | null
        }) =>
          o.objectType === 'expense' &&
          o.description === 'Lunch (filed for Bob)'
      )
      expect(expense).toBeDefined()
      expect(expense.userId).toBe(secondUserId)
      expect(expense.createdByUserId).not.toBe(secondUserId)

      // UI: row should show "filed by" attribution
      const row = page
        .getByTestId('expense-row')
        .filter({ hasText: 'Lunch (filed for Bob)' })
      await expect(row.getByTestId('filed-by')).toBeVisible()
    })

    test('can create an expense with specific participants via the wizard', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(
        page.getByRole('button', { name: 'Add expense' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
      await page.getByRole('button', { name: 'Add expense' }).click()

      // Step 1: Details
      await expect(page.getByTestId('expense-description-input')).toBeVisible()
      await page.getByTestId('expense-description-input').fill('Dinner for Bob')
      await page.getByTestId('expense-amount-input').fill('30')
      await page.getByTestId('submit-button').click()

      // Step 2: Date — just proceed with defaults
      await expect(page.getByTestId('toggle-date-mode')).toBeVisible()
      await page.getByTestId('submit-button').click()

      // Step 3: People — switch to specific people and select second user
      await expect(page.getByTestId('toggle-people-mode')).toBeVisible()

      // Click "Specific people" in the segmented control
      await page
        .getByTestId('toggle-people-mode')
        .getByRole('button', { name: 'Specific people' })
        .click()

      // Select the second user
      const checkbox = page.getByTestId(`participant-${secondUserId}`)
      await expect(checkbox).toBeVisible()
      await checkbox.click()

      // Submit the expense — wait for the API response
      const [createResponse] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/expenses') &&
            resp.request().method() === 'POST'
        ),
        page.getByTestId('submit-button').click(),
      ])
      expect(createResponse.status()).toBe(201)

      // Expense should appear in the list
      const row = page
        .getByTestId('expense-row')
        .filter({ hasText: 'Dinner for Bob' })
      await expect(row).toBeVisible()
      await expect(row.getByText('€30.00')).toBeVisible()

      // Expand the row and verify "Equal split" label
      await row.click()
      await expect(row.getByText('Equal split')).toBeVisible()
      await expect(row.getByText(SECOND_NAME)).toBeVisible()

      // Verify via API that participants were saved
      const expensesResp = await apiContext.get(
        `${API_BASE}/api/expenses?event_id=${eventId}`
      )
      const expensesBody = await expensesResp.json()
      const expense = expensesBody.objects.find(
        (o: { objectType: string; description: string }) =>
          o.objectType === 'expense' && o.description === 'Dinner for Bob'
      )
      expect(expense).toBeDefined()
      expect(expense.participantIds.length).toBeGreaterThan(0)

      const participants = expensesBody.objects.filter(
        (o: { objectType: string; expenseId: string }) =>
          o.objectType === 'expenseParticipant' && o.expenseId === expense.id
      )
      expect(participants.length).toBe(1)
      expect(participants[0].userId).toBe(secondUserId)
    })
  })
})
