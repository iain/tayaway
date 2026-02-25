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
  PAGE_LOAD_TIMEOUT,
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
      apiContext = await playwright.request.newContext()
      await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      eventId = await createBareEvent(apiContext, 'Expense API Test Event')
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
          start_date: '2026-03-01',
          end_date: '2026-03-03',
        },
      })
      expect(createResponse.status()).toBe(201)
      const createBody = await createResponse.json()
      const created = getObjectByType(createBody.objects, 'expense')
      expect(created).toHaveProperty('id')
      expect(created?.description).toBe('Team dinner')
      expect(created?.amount).toBeCloseTo(120.5)
      expect(created).toHaveProperty('eventId', eventId)
      expect(created).toHaveProperty('startDate', '2026-03-01')
      expect(created).toHaveProperty('endDate', '2026-03-03')
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
        { data: { start_date: '2026-03-02', end_date: '2026-03-04' } }
      )
      expect(updateDatesResponse.ok()).toBeTruthy()
      const updateDatesBody = await updateDatesResponse.json()
      const updatedDates = getObjectByType(updateDatesBody.objects, 'expense')
      expect(updatedDates).toHaveProperty('startDate', '2026-03-02')
      expect(updatedDates).toHaveProperty('endDate', '2026-03-04')

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
          start_date: '2026-04-01',
          end_date: '2026-04-03',
          id,
        },
      })
      expect(first.status()).toBe(201)

      const second = await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Hotel',
          amount: 200,
          start_date: '2026-04-01',
          end_date: '2026-04-03',
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

  test.describe('Expenses - Creator-only enforcement', () => {
    let ownerContext: APIRequestContext
    let otherContext: APIRequestContext
    let eventId: string
    let expenseId: string

    test.beforeAll(async ({ playwright }) => {
      ownerContext = await playwright.request.newContext()
      await getTestSession(ownerContext, TEST_EMAIL, TEST_NAME)
      eventId = await createBareEvent(ownerContext, 'Auth Test Event')

      // Create an expense as owner
      const resp = await ownerContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Taxi',
          amount: 30,
          start_date: '2026-01-01',
          end_date: '2026-01-02',
        },
      })
      const body = await resp.json()
      expenseId = getObjectByType(body.objects, 'expense')!.id

      // Create a second user and add them to the same workspace
      otherContext = await playwright.request.newContext()
      await getTestSession(
        otherContext,
        'e2e-expenses-other@example.com',
        'Other E2E User'
      )

      // Get the owner's workspace id
      const wsResp = await ownerContext.get(`${API_BASE}/api/workspaces`)
      const wsBody = await wsResp.json()
      const workspace = getObjectByType(wsBody.objects, 'workspace')!

      // Add other user as member
      await addMemberToWorkspace(
        ownerContext,
        workspace.id,
        'e2e-expenses-other@example.com'
      )
    })

    test.afterAll(async () => {
      await ownerContext.dispose()
      await otherContext.dispose()
    })

    test('non-creator cannot update another user expense', async () => {
      const response = await otherContext.put(
        `${API_BASE}/api/expenses/${expenseId}`,
        { data: { description: 'Hacked' } }
      )
      expect(response.status()).toBe(403)
    })

    test('non-creator cannot delete another user expense', async () => {
      const response = await otherContext.delete(
        `${API_BASE}/api/expenses/${expenseId}`
      )
      expect(response.status()).toBe(403)
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
      const apiContext = await playwright.request.newContext()
      const { token } = await getTestSession(
        apiContext,
        SPLIT_USER_A_EMAIL,
        SPLIT_USER_A_NAME
      )
      const eventId = await createBareEvent(apiContext, 'No Dates Split Test')
      await apiContext.dispose()

      await setupAuthenticatedPage(page, token)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(page.getByRole('heading', { name: 'Expenses' })).toBeVisible(
        { timeout: PAGE_LOAD_TIMEOUT }
      )
      await expect(
        page.getByRole('heading', { name: 'Cost Split' })
      ).not.toBeVisible()
    })

    test('shows split for single attendee with settled balance', async ({
      page,
      playwright,
    }) => {
      const apiContext = await playwright.request.newContext()
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
        page.getByRole('heading', { name: 'Cost Split' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Single attendee is settled (they paid exactly their share)
      await expect(page.getByText('settled')).toBeVisible()
    })

    test('shows correct per-person balances with two attendees', async ({
      page,
      playwright,
    }) => {
      // User A creates event and is auto-RSVP'd attending after poll close
      const apiContextA = await playwright.request.newContext()
      const { token: tokenA } = await getTestSession(
        apiContextA,
        SPLIT_USER_A_EMAIL,
        SPLIT_USER_A_NAME
      )
      const { eventId } = await createResolvedEvent(apiContextA)

      // Add User B to the workspace and have them RSVP attending
      const apiContextB = await playwright.request.newContext()
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
        page.getByRole('heading', { name: 'Cost Split' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // User A: paid €100, fair share €50.00 → owed €50.00 back
      const splitTable = page.getByTestId('cost-split-table')
      const rowA = splitTable
        .getByRole('row')
        .filter({ hasText: SPLIT_USER_A_NAME })
      await expect(rowA.getByText('€100.00', { exact: true })).toBeVisible()
      await expect(rowA.getByText('€50.00', { exact: true })).toBeVisible()
      await expect(rowA.getByText('owed €50.00')).toBeVisible()

      // User B: paid €0.00, fair share €50.00 → owes €50.00
      const rowB = splitTable
        .getByRole('row')
        .filter({ hasText: SPLIT_USER_B_NAME })
      await expect(rowB.getByText('€0.00', { exact: true })).toBeVisible()
      await expect(rowB.getByText('€50.00', { exact: true })).toBeVisible()
      await expect(rowB.getByText('owes €50.00')).toBeVisible()
    })

    test('date-scoped expense only splits among overlapping attendees', async ({
      page,
      playwright,
    }) => {
      // User A creates event, both attend, but User B only attends partial dates
      const apiContextA = await playwright.request.newContext()
      const { token: tokenA } = await getTestSession(
        apiContextA,
        SPLIT_USER_A_EMAIL,
        SPLIT_USER_A_NAME
      )
      const { eventId } = await createResolvedEvent(
        apiContextA,
        'Date Scoped Split'
      )

      const apiContextB = await playwright.request.newContext()
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
        page.getByRole('heading', { name: 'Cost Split' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // User A paid €60, fair share is €60 (100%) → settled
      const splitTable = page.getByTestId('cost-split-table')
      const rowA = splitTable
        .getByRole('row')
        .filter({ hasText: SPLIT_USER_A_NAME })
      await expect(rowA.getByText('settled')).toBeVisible()

      // User B: fair share €0.00, paid €0.00 → settled
      const rowB = splitTable
        .getByRole('row')
        .filter({ hasText: SPLIT_USER_B_NAME })
      await expect(rowB.getByText('settled')).toBeVisible()
    })

    test('expense row expansion shows payer breakdown', async ({
      page,
      playwright,
    }) => {
      const apiContextA = await playwright.request.newContext()
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
      apiContext = await playwright.request.newContext()
      const { token } = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      sessionToken = token
      eventId = await createBareEvent(apiContext, `UI Expense Event ${uid}`)
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
        page.getByRole('heading', { name: 'Expenses' })
      ).toBeVisible()
    })

    test('shows empty state and add expense button', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(page.getByText(/no expenses recorded/i)).toBeVisible({
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

      await expect(
        page.getByPlaceholder('What was this expense for?')
      ).toBeVisible()
      await page
        .getByPlaceholder('What was this expense for?')
        .fill(description)
      await page.getByPlaceholder('0.00').fill('4.50')
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
          start_date: '2026-01-01',
          end_date: '2026-01-02',
        },
      })
      await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Total Item B',
          amount: 5.5,
          start_date: '2026-01-01',
          end_date: '2026-01-02',
        },
      })

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      // Total should include all expenses for this event (at least A + B = 15.50)
      await expect(page.getByText(/€\d+\.\d{2} total/)).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
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
          start_date: '2026-01-01',
          end_date: '2026-01-02',
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
        row.getByRole('button').first().click(),
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
})
