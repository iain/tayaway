import { test, expect, Page, APIRequestContext } from '@playwright/test'

const API_BASE = 'http://localhost:9293'
const TEST_EMAIL = 'e2e-poll@example.com'
const TEST_NAME = 'E2E Poll User'

interface PoolObject {
  id: string
  objectType: string
  [key: string]: unknown
}

function getObjectByType<T extends PoolObject>(
  objects: PoolObject[],
  type: string
): T | undefined {
  return objects.find((o) => o.objectType === type) as T | undefined
}

function getObjectsByType<T extends PoolObject>(
  objects: PoolObject[],
  type: string
): T[] {
  return objects.filter((o) => o.objectType === type) as T[]
}

async function getTestSession(
  request: APIRequestContext,
  email = TEST_EMAIL,
  name = TEST_NAME
): Promise<{ token: string; userId: string }> {
  const response = await request.post(`${API_BASE}/api/test/session`, {
    data: { email, name },
  })
  if (!response.ok()) {
    throw new Error(`Failed to create test session: ${response.status()}`)
  }
  const body = await response.json()
  return { token: body.session_token, userId: body.user_id }
}

function authHeaders(token: string): { Authorization: string } {
  return { Authorization: `Bearer ${token}` }
}

async function setupAuthenticatedPage(
  page: Page,
  token: string
): Promise<void> {
  await page.goto('/')
  await page.evaluate((t) => {
    localStorage.setItem('session_token', t)
  }, token)
}

// Create a bare event (no poll) via API
async function createBareEvent(
  request: APIRequestContext,
  token: string,
  name = 'Poll Lifecycle Event'
): Promise<string> {
  const response = await request.post(`${API_BASE}/api/events`, {
    headers: authHeaders(token),
    data: { name, description: 'Testing poll lifecycle' },
  })
  const body = await response.json()
  const event = getObjectByType(body.objects, 'event')
  return event!.id
}

// Create an event with an open poll and date ranges via API
async function createEventWithPoll(
  request: APIRequestContext,
  token: string
): Promise<{ eventId: string; dateRangeIds: string[] }> {
  const eventId = await createBareEvent(request, token)

  // Open poll
  const deadline = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()
  await request.post(`${API_BASE}/api/events/${eventId}/poll`, {
    headers: authHeaders(token),
    data: { deadline },
  })

  // Add two date ranges
  const dr1Response = await request.post(
    `${API_BASE}/api/events/${eventId}/poll/date-ranges`,
    {
      headers: authHeaders(token),
      data: { start_date: '2026-06-01', end_date: '2026-06-07' },
    }
  )
  const dr1Body = await dr1Response.json()
  const dr1 = getObjectByType(dr1Body.objects, 'dateRange')

  const dr2Response = await request.post(
    `${API_BASE}/api/events/${eventId}/poll/date-ranges`,
    {
      headers: authHeaders(token),
      data: { start_date: '2026-06-15', end_date: '2026-06-20' },
    }
  )
  const dr2Body = await dr2Response.json()
  const dr2 = getObjectByType(dr2Body.objects, 'dateRange')

  return { eventId, dateRangeIds: [dr1!.id, dr2!.id] }
}

// Create an event with a poll that has votes and is closed (winner selected)
async function createResolvedEvent(
  request: APIRequestContext,
  token: string
): Promise<{ eventId: string; winnerDateRangeId: string }> {
  const { eventId, dateRangeIds } = await createEventWithPoll(request, token)

  // Vote on the first date range
  await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
    headers: authHeaders(token),
    data: { date_range_id: dateRangeIds[0], response: 'yes' },
  })

  // Close poll with the first date range as winner
  await request.post(`${API_BASE}/api/events/${eventId}/poll/close`, {
    headers: authHeaders(token),
    data: { selected_date_range_id: dateRangeIds[0] },
  })

  return { eventId, winnerDateRangeId: dateRangeIds[0] }
}

test.describe('Poll Lifecycle UI', () => {
  test.describe('Opening a poll', () => {
    test('event page shows "Open Date Poll" button when no poll exists', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const eventId = await createBareEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      await expect(
        page.getByRole('button', { name: 'Open Date Poll' })
      ).toBeVisible()
    })

    test('clicking "Open Date Poll" opens modal with deadline field', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const eventId = await createBareEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      await page.getByRole('button', { name: 'Open Date Poll' }).click()

      // Modal should appear with deadline input
      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(page.getByLabel('Voting Deadline')).toBeVisible()
      await expect(
        page.getByRole('button', { name: 'Open Poll', exact: true })
      ).toBeVisible()
    })

    test('can open a date poll through the modal', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const eventId = await createBareEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      // Open the modal
      await page.getByRole('button', { name: 'Open Date Poll' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()

      // The deadline input has a default value (7 days from now)
      // Just confirm with the default
      await page.getByRole('button', { name: 'Open Poll', exact: true }).click()

      // Modal should close and poll status should appear
      await expect(page.getByRole('dialog')).not.toBeVisible()
      await expect(page.getByText(/remaining/)).toBeVisible({ timeout: 5000 })

      // "Add Date Range" button should now be visible
      await expect(
        page.getByRole('button', { name: 'Add Date Range' })
      ).toBeVisible()
    })
  })

  test.describe('Adding date ranges', () => {
    test('clicking "Add Date Range" opens calendar modal', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createEventWithPoll(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      await page.getByRole('button', { name: 'Add Date Range' }).click()

      // Calendar modal should appear
      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(
        page.getByRole('dialog').getByText('Select Date Range')
      ).toBeVisible()
    })

    test('can add a date range by selecting two dates on the calendar', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createEventWithPoll(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      // Should have 2 date ranges initially
      await expect(page.getByText(/votes?$/).first()).toBeVisible({
        timeout: 5000,
      })
      const initialDateRangeCards = page.locator(
        'section:has-text("Date Poll") .rounded-md.border'
      )
      const initialCount = await initialDateRangeCards.count()

      // Open calendar modal
      await page.getByRole('button', { name: 'Add Date Range' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()

      // The calendar is preselected around late June (7 days after Jun 15-20),
      // showing June (left) and July (right) side-by-side. The June calendar's
      // overflow grid extends into early July, so pick late-July dates that
      // only appear in the July calendar.
      await page.getByTestId('calendar-day-2026-07-15').click()
      // Selection text should update
      await expect(page.getByText(/Select end date/)).toBeVisible()

      // Select end date — auto-saves and closes
      await page.getByTestId('calendar-day-2026-07-20').click()

      // Modal should auto-close after selecting the range
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      // New date range should appear in the list
      const afterDateRangeCards = page.locator(
        'section:has-text("Date Poll") .rounded-md.border'
      )
      await expect(afterDateRangeCards).toHaveCount(initialCount + 1, {
        timeout: 5000,
      })
    })

    test('can remove a date range', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createEventWithPoll(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      // Wait for date ranges to load
      const dateRangeCards = page.locator(
        'section:has-text("Date Poll") .rounded-md.border'
      )
      await expect(dateRangeCards.first()).toBeVisible({ timeout: 5000 })
      const initialCount = await dateRangeCards.count()

      // Click "Remove" on the first date range
      await page.getByRole('button', { name: 'Remove' }).first().click()

      // One fewer date range
      await expect(dateRangeCards).toHaveCount(initialCount - 1, {
        timeout: 5000,
      })
    })
  })

  test.describe('Poll status display', () => {
    test('open poll shows remaining time', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createEventWithPoll(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      // Should show time remaining
      await expect(page.getByText(/remaining/)).toBeVisible({ timeout: 5000 })
    })

    test('open poll shows "Vote on Dates" button', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createEventWithPoll(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      await expect(
        page.getByRole('button', { name: 'Vote on Dates' })
      ).toBeVisible({ timeout: 5000 })
    })

    test('resolved poll shows winner badge', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createResolvedEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      await expect(page.getByText('Winner selected')).toBeVisible({
        timeout: 5000,
      })
      await expect(page.getByText('Winner').first()).toBeVisible()
    })
  })

  test.describe('Closing a poll (selecting winner)', () => {
    test('"Select Winner" button opens close poll modal', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createEventWithPoll(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      await page.getByRole('button', { name: 'Select Winner' }).click()

      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(
        page.getByRole('dialog').getByText('Select Winning Date')
      ).toBeVisible()
      await expect(
        page.getByRole('button', { name: 'Confirm Winner' })
      ).toBeVisible()
      // Confirm button should be disabled until a date range is selected
      await expect(
        page.getByRole('button', { name: 'Confirm Winner' })
      ).toBeDisabled()
    })

    test('can select a winner and close the poll', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createEventWithPoll(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      // Open close poll modal
      await page.getByRole('button', { name: 'Select Winner' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()

      // Click the first date range option in the modal
      const dateOption = page
        .getByRole('dialog')
        .locator('button.w-full')
        .first()
      await dateOption.click()

      // Confirm winner
      await page.getByRole('button', { name: 'Confirm Winner' }).click()

      // Modal should close
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      // Poll should now be resolved with winner displayed
      await expect(page.getByText('Winner selected')).toBeVisible({
        timeout: 5000,
      })
      await expect(page.getByText('Winner').first()).toBeVisible()

      // "Reopen Poll" button should be visible
      await expect(
        page.getByRole('button', { name: 'Reopen Poll' })
      ).toBeVisible()

      // "Select Winner" button should no longer be visible
      await expect(
        page.getByRole('button', { name: 'Select Winner' })
      ).not.toBeVisible()
    })
  })

  test.describe('Reopening a poll', () => {
    test('"Reopen Poll" button is visible on resolved poll', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createResolvedEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      await expect(
        page.getByRole('button', { name: 'Reopen Poll' })
      ).toBeVisible({ timeout: 5000 })
    })

    test('clicking "Reopen Poll" opens modal with deadline field', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createResolvedEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      await page.getByRole('button', { name: 'Reopen Poll' }).click()

      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(
        page.getByRole('dialog').getByText('Reopen Date Poll')
      ).toBeVisible()
      await expect(page.getByLabel('Voting Deadline')).toBeVisible()
    })

    test('can reopen a resolved poll', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createResolvedEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      // Verify it's currently resolved
      await expect(page.getByText('Winner selected')).toBeVisible({
        timeout: 5000,
      })

      // Click reopen
      await page.getByRole('button', { name: 'Reopen Poll' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()

      // Confirm with default deadline
      await page.getByRole('button', { name: 'Open Poll', exact: true }).click()

      // Modal should close
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      // Poll should now be open again
      await expect(page.getByText(/remaining/)).toBeVisible({ timeout: 5000 })

      // Winner text should be gone
      await expect(page.getByText('Winner selected')).not.toBeVisible()

      // "Vote on Dates" and "Select Winner" buttons should be back
      await expect(
        page.getByRole('button', { name: 'Vote on Dates' })
      ).toBeVisible()
      await expect(
        page.getByRole('button', { name: 'Select Winner' })
      ).toBeVisible()
    })
  })

  test.describe('Vote page and closed poll', () => {
    test('vote page shows "Voting is closed" when poll is resolved', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createResolvedEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}/vote`)

      await expect(page.getByText('Voting is closed')).toBeVisible({
        timeout: 10000,
      })
      await expect(
        page.getByText('The date poll is no longer accepting votes.')
      ).toBeVisible()
    })

    test('"Vote on Dates" button navigates to vote page', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createEventWithPoll(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      await page
        .getByRole('button', { name: 'Vote on Dates' })
        .click({ timeout: 5000 })

      await expect(page).toHaveURL(`/events/${eventId}/vote`)
      // Should see voting cards for each date range
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).toBeVisible({ timeout: 5000 })
    })
  })

  test.describe('Full lifecycle', () => {
    test('complete poll lifecycle: open → add dates → vote → close → reopen', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const eventId = await createBareEvent(
        request,
        token,
        'Full Lifecycle Event'
      )
      await setupAuthenticatedPage(page, token)

      // 1. Navigate to event page
      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toContainText(
        'Full Lifecycle Event',
        { timeout: 10000 }
      )

      // 2. Open a poll
      await page.getByRole('button', { name: 'Open Date Poll' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page.getByRole('button', { name: 'Open Poll', exact: true }).click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })
      await expect(page.getByText(/remaining/)).toBeVisible({ timeout: 5000 })

      // 3. Add a date range via calendar (calendar opens on current month Feb 2026)
      await page.getByRole('button', { name: 'Add Date Range' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      // Pick dates in the visible months (Feb/Mar 2026)
      await page.getByTestId('calendar-day-2026-03-10').click()
      await page.getByTestId('calendar-day-2026-03-15').click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      // Verify date range appeared
      const dateRangeCards = page.locator(
        'section:has-text("Date Poll") .rounded-md.border'
      )
      await expect(dateRangeCards).toHaveCount(1, { timeout: 5000 })

      // 4. Add a second date range (preselected 7 days after first: Mar 17-22)
      await page.getByRole('button', { name: 'Add Date Range' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page.getByTestId('calendar-day-2026-03-20').click()
      await page.getByTestId('calendar-day-2026-03-25').click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })
      await expect(dateRangeCards).toHaveCount(2, { timeout: 5000 })

      // 5. Navigate to vote page and cast a vote
      await page.getByRole('button', { name: 'Vote on Dates' }).click()
      await expect(page).toHaveURL(`/events/${eventId}/vote`)
      await page
        .getByRole('button', { name: 'Yes', exact: true })
        .first()
        .click()
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).toHaveClass(/bg-green-600/)

      // 6. Go back and close the poll
      await page.getByRole('button', { name: 'Back to Event' }).click()
      await expect(page).toHaveURL(`/events/${eventId}`)
      await page.getByRole('button', { name: 'Select Winner' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()

      // Select the first option and confirm
      await page.getByRole('dialog').locator('button.w-full').first().click()
      await page.getByRole('button', { name: 'Confirm Winner' }).click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })
      await expect(page.getByText('Winner selected')).toBeVisible({
        timeout: 5000,
      })

      // 7. Reopen the poll
      await page.getByRole('button', { name: 'Reopen Poll' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page.getByRole('button', { name: 'Open Poll', exact: true }).click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })
      await expect(page.getByText(/remaining/)).toBeVisible({ timeout: 5000 })
      await expect(page.getByText('Winner selected')).not.toBeVisible()
    })
  })
})
