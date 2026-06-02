import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getTestSession,
  setupAuthenticatedPage,
  createBareEvent,
  createEventWithPoll,
  createResolvedEvent,
  PAGE_LOAD_TIMEOUT,
  newApiContext,
  offsetDate,
  futureCalendarDate,
} from '../helpers'

// Reopening a poll is only allowed while the event hasn't started, so these
// fixtures need a winning range in the future — a hardcoded date would start
// "already started" once wall-clock time passes it.
const FUTURE_RANGES = [
  { start_date: offsetDate(30), end_date: offsetDate(36) },
  { start_date: offsetDate(45), end_date: offsetDate(50) },
]

const TEST_EMAIL = 'e2e-poll@example.com'
const TEST_NAME = 'E2E Poll User'

test.describe('Poll Lifecycle UI', () => {
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

  test.describe('Opening a poll', () => {
    test('can open a date poll through the modal', async ({ page }) => {
      const eventId = await createBareEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/planning`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Open the modal
      await page.getByRole('button', { name: 'Open Date Poll' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()

      // The deadline input has a default value (7 days from now)
      // Just confirm with the default
      await page.getByRole('button', { name: 'Open Poll', exact: true }).click()

      // Modal should close and redirect to date-ranges page
      await expect(page.getByRole('dialog')).not.toBeVisible()
      await expect(page).toHaveURL(`/events/${eventId}/planning/date-ranges`)

      // "Add Date Range" button should be visible on date-ranges page
      await expect(
        page.getByRole('button', { name: 'Add Date Range' }).first()
      ).toBeVisible()
    })
  })

  test.describe('Adding date ranges', () => {
    test('clicking "Add Date Range" opens calendar modal', async ({ page }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/planning/date-ranges`)
      await expect(
        page.getByRole('heading', { name: 'Edit Date Ranges' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      await page.getByRole('button', { name: 'Add Date Range' }).click()

      // Calendar modal should appear
      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(
        page.getByRole('dialog').getByText('Select Date Range')
      ).toBeVisible()
    })

    test('can add a date range by selecting two dates on the calendar', async ({
      page,
    }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/planning/date-ranges`)
      await expect(
        page.getByRole('heading', { name: 'Edit Date Ranges' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Should have 2 date ranges initially
      await expect(page.getByText(/votes?$/).first()).toBeVisible()
      const dateRangeItems = page.getByTestId('date-range-item')
      const initialCount = await dateRangeItems.count()

      // Open calendar modal
      await page.getByRole('button', { name: 'Add Date Range' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()

      // Pick a fresh range a few months out, navigating forward to its month
      // first (the calendar opens around the existing ranges).
      const rangeStart = futureCalendarDate(3, 10)
      const rangeEnd = futureCalendarDate(3, 14)
      while (!(await page.getByText(rangeStart.monthLabel).isVisible())) {
        await page
          .getByRole('dialog')
          .getByRole('button', { name: /next/i })
          .click()
      }
      await page.getByTestId(`calendar-day-${rangeStart.iso}`).first().click()
      // Selection text should update
      await expect(page.getByText(/Select end date/)).toBeVisible()

      // Select end date — auto-saves and closes
      await page.getByTestId(`calendar-day-${rangeEnd.iso}`).first().click()

      // Modal should auto-close after selecting the range
      await expect(page.getByRole('dialog')).not.toBeVisible()

      // New date range should appear in the list
      await expect(dateRangeItems).toHaveCount(initialCount + 1)
    })

    test('can remove a date range', async ({ page }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/planning/date-ranges`)
      await expect(
        page.getByRole('heading', { name: 'Edit Date Ranges' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Wait for date ranges to load
      const dateRangeItems = page.getByTestId('date-range-item')
      await expect(dateRangeItems.first()).toBeVisible()
      const initialCount = await dateRangeItems.count()

      // Click "Remove" on the first date range (no votes, no confirmation dialog)
      await page.getByRole('button', { name: 'Remove' }).first().click()

      // One fewer date range
      await expect(dateRangeItems).toHaveCount(initialCount - 1)
    })
  })

  test.describe('Poll status display', () => {
    let openEventId: string
    let resolvedEventId: string

    test.beforeAll(async () => {
      const { eventId: eid1 } = await createEventWithPoll(apiContext)
      openEventId = eid1
      const { eventId: eid2 } = await createResolvedEvent(
        apiContext,
        'Test Event',
        FUTURE_RANGES
      )
      resolvedEventId = eid2
    })

    test('open poll shows remaining time and "Vote on Dates" button', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${openEventId}/planning`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await expect(page.getByText(/remaining/)).toBeVisible()
      await expect(
        page.getByRole('button', { name: 'Vote on Dates' })
      ).toBeVisible()
    })

    test('resolved poll shows winner badge', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${resolvedEventId}/planning`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await expect(
        page.getByRole('button', { name: 'Reopen Poll' })
      ).toBeVisible()
      await expect(page.getByTestId('event-dates')).toBeVisible()
    })
  })

  test.describe('Closing a poll (selecting winner)', () => {
    test('closing a poll populates event dates from winning date range', async ({
      page,
    }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/planning`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Event should not show dates before poll is closed
      await expect(page.getByTestId('event-dates')).not.toBeVisible()

      // Close the poll by selecting the first date range (Jun 1-7)
      await page.getByRole('button', { name: 'Select Winner' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page
        .getByRole('dialog')
        .getByTestId('date-range-option')
        .first()
        .click()
      await page.getByRole('button', { name: 'Confirm Winner' }).click()
      await expect(page.getByRole('dialog')).not.toBeVisible()

      // Event header should now show dates from the winning date range
      await expect(page.getByTestId('event-dates')).toBeVisible()
      await expect(page.getByTestId('event-dates')).toContainText(/Jun/)
    })
  })

  test.describe('Reopening a poll', () => {
    test('can reopen a resolved poll', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Test Event',
        FUTURE_RANGES
      )
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/planning`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Verify it's currently resolved
      await expect(
        page.getByRole('button', { name: 'Reopen Poll' })
      ).toBeVisible()

      // Click reopen
      await page.getByRole('button', { name: 'Reopen Poll' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()

      // Confirm with default deadline
      await page.getByRole('button', { name: 'Open Poll', exact: true }).click()

      // Modal should close
      await expect(page.getByRole('dialog')).not.toBeVisible()

      // Poll should now be open again
      await expect(page.getByText(/remaining/)).toBeVisible()

      // Reopen Poll button should be gone (poll is now open)
      await expect(
        page.getByRole('button', { name: 'Reopen Poll' })
      ).not.toBeVisible()

      // "Vote on Dates" and "Select Winner" buttons should be back
      await expect(
        page.getByRole('button', { name: 'Vote on Dates' })
      ).toBeVisible()
      await expect(
        page.getByRole('button', { name: 'Select Winner' })
      ).toBeVisible()
    })

    test('reopening a poll clears event dates', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Test Event',
        FUTURE_RANGES
      )
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/planning`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Resolved event should show dates from the winning date range
      await expect(page.getByTestId('event-dates')).toBeVisible()
      await expect(page.getByTestId('event-dates')).not.toBeEmpty()

      // Reopen the poll
      await page.getByRole('button', { name: 'Reopen Poll' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page.getByRole('button', { name: 'Open Poll', exact: true }).click()
      await expect(page.getByRole('dialog')).not.toBeVisible()

      // Event dates should be cleared
      await expect(page.getByTestId('event-dates')).not.toBeVisible()
    })
  })

  test.describe('Vote page and closed poll', () => {
    let openEventId: string
    let resolvedEventId: string

    test.beforeAll(async () => {
      const { eventId: eid1 } = await createEventWithPoll(apiContext)
      openEventId = eid1
      const { eventId: eid2 } = await createResolvedEvent(apiContext)
      resolvedEventId = eid2
    })

    test('vote page shows "Voting has ended" when poll is resolved', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${resolvedEventId}/planning/vote`)

      await expect(page.getByTestId('poll-closed-message')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(page.getByTestId('poll-closed-message')).toContainText(
        'The date poll is closed and no longer accepting votes.'
      )
    })

    test('"Vote on Dates" button navigates to vote page', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${openEventId}/planning`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page
        .getByRole('button', { name: 'Vote on Dates' })
        .click({ timeout: 5000 })

      await expect(page).toHaveURL(`/events/${openEventId}/planning/vote`)
      // Should see voting cards for each date range
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).toBeVisible()
    })
  })

  test.describe('Full lifecycle', () => {
    test('complete poll lifecycle: open → add dates → vote → close → reopen', async ({
      page,
    }) => {
      // Pick dates dynamically in the month after today so the event is
      // always in the future — otherwise closing the poll resolves to an
      // already-started event and the "Reopen Poll" button is hidden.
      //
      // Day numbers must stay within 15..22: CalendarMonth renders a 6-week
      // (42-cell) grid, so days 1..14 of a month also appear as overflow in
      // the previous month's grid (ambiguous `calendar-day-YYYY-MM-DD`
      // testids when both months are shown side-by-side), and the last ~6
      // days of a month can appear as leading overflow in the next month's
      // grid. The second-range preselection of first+7 also stays inside
      // the same month as long as we're in this band.
      const today = new Date()
      const nextMonthDate = new Date(
        today.getFullYear(),
        today.getMonth() + 1,
        1
      )
      const yy = nextMonthDate.getFullYear()
      const mm = String(nextMonthDate.getMonth() + 1).padStart(2, '0')
      const r1Start = `${yy}-${mm}-15`
      const r1End = `${yy}-${mm}-17`
      const r2Start = `${yy}-${mm}-20`
      const r2End = `${yy}-${mm}-22`

      const eventId = await createBareEvent(apiContext, 'Full Lifecycle Event')
      await setupAuthenticatedPage(page, sessionToken)

      // 1. Navigate to event planning page
      await page.goto(`/events/${eventId}/planning`)
      await expect(page.getByTestId('event-name')).toContainText(
        'Full Lifecycle Event',
        { timeout: PAGE_LOAD_TIMEOUT }
      )

      // 2. Open a poll — redirects to date-ranges page
      await page.getByRole('button', { name: 'Open Date Poll' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page.getByRole('button', { name: 'Open Poll', exact: true }).click()
      await expect(page.getByRole('dialog')).not.toBeVisible()
      await expect(page).toHaveURL(`/events/${eventId}/planning/date-ranges`)

      // 3. Add a date range via calendar
      await page.getByRole('button', { name: 'Add Date Range' }).first().click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page.getByTestId(`calendar-day-${r1Start}`).click()
      await page.getByTestId(`calendar-day-${r1End}`).click()
      await expect(page.getByRole('dialog')).not.toBeVisible()

      // Verify date range appeared
      const dateRangeItems = page.getByTestId('date-range-item')
      await expect(dateRangeItems).toHaveCount(1)

      // 4. Add a second date range
      await page.getByRole('button', { name: 'Add Date Range' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page.getByTestId(`calendar-day-${r2Start}`).click()
      await page.getByTestId(`calendar-day-${r2End}`).click()
      await expect(page.getByRole('dialog')).not.toBeVisible()
      await expect(dateRangeItems).toHaveCount(2)

      // 5. Navigate to planning, then to vote page
      await page.getByRole('link', { name: 'Planning' }).click()
      await expect(page).toHaveURL(`/events/${eventId}/planning`)
      await page.getByRole('button', { name: 'Vote on Dates' }).click()
      await expect(page).toHaveURL(`/events/${eventId}/planning/vote`)
      await page
        .getByRole('button', { name: 'Yes', exact: true })
        .first()
        .click()
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).toHaveAttribute('aria-pressed', 'true')

      // 6. Go back to planning and close the poll
      await page.getByRole('link', { name: 'Planning' }).click()
      await expect(page).toHaveURL(`/events/${eventId}/planning`)
      await page.getByRole('button', { name: 'Select Winner' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()

      // Select the first option and confirm
      await page
        .getByRole('dialog')
        .getByTestId('date-range-option')
        .first()
        .click()
      await page.getByRole('button', { name: 'Confirm Winner' }).click()
      await expect(page.getByRole('dialog')).not.toBeVisible()
      // Wait for event dates to appear (confirms close-poll broadcasts have settled)
      await expect(page.getByTestId('event-dates')).toBeVisible()
      await expect(
        page.getByRole('button', { name: 'Reopen Poll' })
      ).toBeVisible()

      // 7. Reopen the poll
      await page.getByRole('button', { name: 'Reopen Poll' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page.getByRole('button', { name: 'Open Poll', exact: true }).click()
      await expect(page.getByRole('dialog')).not.toBeVisible()
      await expect(page.getByText(/remaining/)).toBeVisible()
      await expect(
        page.getByRole('button', { name: 'Reopen Poll' })
      ).not.toBeVisible()
    })
  })
})
