import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getTestSession,
  setupAuthenticatedPage,
  createEventWithPoll,
  createResolvedEvent,
  getObjectsByType,
  getWorkspaceId,
  addMemberToWorkspace,
  PAGE_LOAD_TIMEOUT,
  newApiContext,
  RESOLVED_EVENT_START,
  RESOLVED_EVENT_END,
} from '../helpers'

// Add whole days to an ISO date, UTC-anchored to stay DST-proof.
function isoAddDays(iso: string, days: number): string {
  const date = new Date(`${iso}T00:00:00Z`)
  date.setUTCDate(date.getUTCDate() + days)
  return date.toISOString().slice(0, 10)
}

const TEST_EMAIL = 'e2e-rsvp@example.com'
const TEST_NAME = 'E2E RSVP User'

test.describe('RSVP Feature', () => {
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

  test.describe('RSVP section visibility', () => {
    test('RSVP section is not visible when event has no dates', async ({
      page,
    }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // No dates set, so RSVP section should not be visible
      await expect(page.getByTestId('rsvp-section')).not.toBeVisible()
    })

    test('RSVP section appears when event has dates (poll closed)', async ({
      page,
    }) => {
      const { eventId } = await createResolvedEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/rsvp`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Resolved event has dates from winning date range
      await expect(page.getByTestId('rsvp-section')).toBeVisible()
    })
  })

  test.describe('RSVP actions', () => {
    test('can change RSVP from attending to not attending', async ({
      page,
    }) => {
      const { eventId } = await createResolvedEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/rsvp`)
      await expect(page.getByTestId('rsvp-section')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // First attend
      await page.getByTestId('rsvp-attend').click()
      await expect(page.getByTestId('rsvp-attend')).toHaveAttribute(
        'aria-pressed',
        'true'
      )

      // Then decline
      await page.getByTestId('rsvp-decline').click()
      await expect(page.getByTestId('rsvp-decline')).toHaveAttribute(
        'aria-pressed',
        'true'
      )
      // Attend button should no longer be active
      await expect(page.getByTestId('rsvp-attend')).toHaveAttribute(
        'aria-pressed',
        'false'
      )
    })
  })

  test.describe('Come-and-go attendance', () => {
    test('picking specific days stores a partial attendance set', async ({
      page,
    }) => {
      // Creator is auto-RSVPed as attending the whole event.
      const { eventId } = await createResolvedEvent(apiContext, 'Come and go')
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/rsvp`)
      await expect(page.getByTestId('rsvp-section')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Open the day picker (preset to every day) and drop the last day so the
      // selection becomes non-whole-event "come and go".
      await page.getByTestId('rsvp-change-dates').click()
      await page.getByTestId(`calendar-day-${RESOLVED_EVENT_END}`).click()

      const [postResponse] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes(`/api/events/${eventId}/attendances`) &&
            resp.request().method() === 'POST'
        ),
        page.getByRole('button', { name: 'Save' }).click(),
      ])
      expect(postResponse.ok()).toBeTruthy()

      // The attendee card now shows a partial-days summary.
      await expect(page.getByTestId('rsvp-attendance-days')).toBeVisible()

      // Backend stored the explicit day set (every day but the last).
      const attendancesResp = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/attendances`
      )
      const attendances = getObjectsByType(
        (await attendancesResp.json()).objects,
        'attendance'
      ) as Array<{ status: string; days: string[] | null }>
      expect(attendances.length).toBe(1)
      expect(attendances[0]!.status).toBe('going')
      expect(attendances[0]!.days).not.toBeNull()
      expect(attendances[0]!.days).not.toContain(RESOLVED_EVENT_END)
      expect(attendances[0]!.days!.length).toBe(6)
    })

    test('shift-click selects a range, re-adding the days in between', async ({
      page,
    }) => {
      const { eventId } = await createResolvedEvent(apiContext, 'Shift range')
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/rsvp`)
      await expect(page.getByTestId('rsvp-section')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      const dayCell = (iso: string) => page.getByTestId(`calendar-day-${iso}`)
      const d = (offset: number) => isoAddDays(RESOLVED_EVENT_START, offset)

      await page.getByTestId('rsvp-change-dates').click()

      // Every day starts selected. Drop the last day (so the set never
      // normalises to "whole event") plus two interior days, leaving gaps —
      // each click also moves the range anchor to that day.
      await dayCell(RESOLVED_EVENT_END).click()
      await dayCell(d(2)).click()
      await dayCell(d(4)).click() // anchor is now day+4

      // Shift-click back to day+1 selects the whole day+1..day+4 range, which
      // re-adds the two interior days we just removed.
      await dayCell(d(1)).click({ modifiers: ['Shift'] })

      const [postResponse] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes(`/api/events/${eventId}/attendances`) &&
            resp.request().method() === 'POST'
        ),
        page.getByRole('button', { name: 'Save' }).click(),
      ])
      expect(postResponse.ok()).toBeTruthy()

      const attendancesResp = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/attendances`
      )
      const attendances = getObjectsByType(
        (await attendancesResp.json()).objects,
        'attendance'
      ) as Array<{ days: string[] | null }>
      expect(attendances.length).toBe(1)
      // day..day+5 attended (6 days); the last day stays dropped, and the two
      // interior days the shift-range crossed are back.
      expect(attendances[0]!.days).not.toBeNull()
      expect(attendances[0]!.days).toContain(d(2))
      expect(attendances[0]!.days).toContain(d(4))
      expect(attendances[0]!.days).not.toContain(RESOLVED_EVENT_END)
      expect(attendances[0]!.days!.length).toBe(6)
    })
  })

  test.describe('Cannot decline with expenses', () => {
    test('shows dialog when declining RSVP with expenses on the event', async ({
      page,
    }) => {
      // Create resolved event (auto-RSVPs the user as attending)
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Decline With Expenses'
      )

      // Add an expense
      await apiContext.post(`${API_BASE}/api/expenses`, {
        data: {
          event_id: eventId,
          description: 'Hotel',
          amount: 50,
          start_date: RESOLVED_EVENT_START,
          end_date: RESOLVED_EVENT_END,
        },
      })

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/rsvp`)

      await expect(page.getByTestId('rsvp-section')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Try to decline
      await page.getByTestId('rsvp-decline').click()

      // Dialog should appear with explanation
      await expect(
        page.getByText('You have expenses on this event')
      ).toBeVisible()
      await expect(
        page.getByRole('link', { name: 'Go to Expenses' })
      ).toBeVisible()

      // RSVP should still be attending
      await expect(page.getByTestId('rsvp-attend')).toHaveAttribute(
        'aria-pressed',
        'true'
      )

      // Link should navigate to expenses page
      await page.getByRole('link', { name: 'Go to Expenses' }).click()
      await expect(page).toHaveURL(`/events/${eventId}/expenses`)
    })
  })

  test.describe('Auto-RSVP on poll close', () => {
    test('closing a poll auto-RSVPs yes-voters as attending', async ({
      page,
    }) => {
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      // Vote "yes" on the first date range
      await apiContext.post(`${API_BASE}/api/events/${eventId}/votes`, {
        data: { date_range_id: dateRangeId, response: 'yes' },
      })

      // Close the poll selecting the first date range
      await apiContext.post(`${API_BASE}/api/events/${eventId}/poll/close`, {
        data: { selected_date_range_id: dateRangeId },
      })

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/rsvp`)
      await expect(page.getByTestId('rsvp-section')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // User should be auto-RSVPed as attending
      await expect(page.getByTestId('rsvp-attend')).toHaveAttribute(
        'aria-pressed',
        'true'
      )
    })
  })

  test.describe('On-behalf-of RSVP actions', () => {
    const OTHER_EMAIL = 'e2e-rsvp-other@example.com'
    const OTHER_NAME = 'E2E RSVP Other'

    let otherUserId: string
    let eventId: string

    test.beforeAll(async ({ playwright }) => {
      const workspaceId = await getWorkspaceId(apiContext)

      const otherContext = await newApiContext(playwright)
      ;({ userId: otherUserId } = await getTestSession(
        otherContext,
        OTHER_EMAIL,
        OTHER_NAME
      ))
      await otherContext.dispose()

      await addMemberToWorkspace(apiContext, workspaceId, OTHER_EMAIL)
      ;({ eventId } = await createResolvedEvent(apiContext, 'On-behalf RSVP'))
    })

    test('a member can file an RSVP for another member from the kebab menu', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/rsvp`)
      await expect(page.getByTestId('rsvp-section')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      const otherRow = page.locator('li').filter({ hasText: OTHER_NAME })
      await expect(otherRow).toBeVisible()

      await otherRow.getByTestId('rsvp-other-menu').click()

      const [postResponse] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes(`/api/events/${eventId}/attendances`) &&
            resp.request().method() === 'POST'
        ),
        page.getByRole('menuitem', { name: 'Mark as attending' }).click(),
      ])
      expect(postResponse.ok()).toBeTruthy()

      // Expect the row to move into the Attending list
      await expect(
        page
          .getByRole('heading', { name: /^Attending/ })
          .locator('xpath=following-sibling::ul[1]')
          .filter({ hasText: OTHER_NAME })
      ).toBeVisible()

      // Verify backend recorded the actor as filer and the subject as the other user
      const attendancesResp = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/attendances`
      )
      const attendances = getObjectsByType(
        (await attendancesResp.json()).objects,
        'attendance'
      ) as Array<{
        userId: string | null
        status: string
        createdByUserId: string | null
      }>
      const onBehalf = attendances.find((a) => a.userId === otherUserId)
      expect(onBehalf).toBeDefined()
      expect(onBehalf!.status).toBe('going')
      expect(onBehalf!.createdByUserId).not.toBe(otherUserId)
    })
  })

  test.describe('Auto-RSVP via API', () => {
    test('poll close returns RSVP objects for yes-voters', async () => {
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      // Vote "yes" on the first date range
      await apiContext.post(`${API_BASE}/api/events/${eventId}/votes`, {
        data: { date_range_id: dateRangeId, response: 'yes' },
      })

      // Close the poll
      const closeResponse = await apiContext.post(
        `${API_BASE}/api/events/${eventId}/poll/close`,
        { data: { selected_date_range_id: dateRangeId } }
      )
      const closeBody = await closeResponse.json()
      const attendances = getObjectsByType(closeBody.objects, 'attendance')

      expect(attendances.length).toBe(1)
      expect(attendances[0]!.status).toBe('going')
    })

    test('poll reopen reverts attendances to pending', async () => {
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      // Vote + close
      await apiContext.post(`${API_BASE}/api/events/${eventId}/votes`, {
        data: { date_range_id: dateRangeId, response: 'yes' },
      })
      await apiContext.post(`${API_BASE}/api/events/${eventId}/poll/close`, {
        data: { selected_date_range_id: dateRangeId },
      })

      // Close marked the yes-voter as going
      const attendanceResponse = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/attendances`
      )
      const before = getObjectsByType(
        (await attendanceResponse.json()).objects,
        'attendance'
      )
      expect(before.length).toBe(1)
      expect(before[0]!.status).toBe('going')

      // Reopen poll
      const deadline = new Date(
        Date.now() + 7 * 24 * 60 * 60 * 1000
      ).toISOString()
      await apiContext.post(`${API_BASE}/api/events/${eventId}/poll/reopen`, {
        data: { deadline },
      })

      // The roster survives; the answer resets to pending
      const attendanceResponse2 = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/attendances`
      )
      const after = getObjectsByType(
        (await attendanceResponse2.json()).objects,
        'attendance'
      )
      expect(after.length).toBe(1)
      expect(after[0]!.status).toBe('pending')
    })
  })

  // The per-day plus-ones settlement test that lived here was retired with
  // the stepper UI (doc/attendances.md phase 4); its settlement-shift
  // coverage returns with the phase-5 settlement flip, computed from named
  // guest attendances (see settlement e2e).
})
