import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getTestSession,
  setupAuthenticatedPage,
  createBareEvent,
  createEventWithPoll,
  createResolvedEvent,
  PAGE_LOAD_TIMEOUT,
} from '../helpers'

const TEST_EMAIL = 'e2e-poll@example.com'
const TEST_NAME = 'E2E Poll User'

test.describe('Poll Lifecycle UI', () => {
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

  test.describe('Opening a poll', () => {
    test('can open a date poll through the modal', async ({ page }) => {
      const eventId = await createBareEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
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
      const { eventId: eid2 } = await createResolvedEvent(apiContext)
      resolvedEventId = eid2
    })

    test('open poll shows remaining time and "Vote on Dates" button', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${openEventId}`)
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

      await page.goto(`/events/${eventId}`)
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
      const { eventId } = await createResolvedEvent(apiContext)
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
      const { eventId } = await createResolvedEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/planning`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Resolved event should show dates from winning date range (Jun 1-7)
      await expect(page.getByTestId('event-dates')).toBeVisible()
      await expect(page.getByTestId('event-dates')).toContainText(/Jun/)

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

    test('vote page shows "Voting is closed" when poll is resolved', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${resolvedEventId}/planning/vote`)

      await expect(page.getByText('Voting is closed')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(
        page.getByText('The date poll is no longer accepting votes.')
      ).toBeVisible()
    })

    test('"Vote on Dates" button navigates to vote page', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${openEventId}`)
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
      const eventId = await createBareEvent(apiContext, 'Full Lifecycle Event')
      await setupAuthenticatedPage(page, sessionToken)

      // 1. Navigate to event page
      await page.goto(`/events/${eventId}`)
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

      // 3. Add a date range via calendar (calendar opens on current month Feb 2026)
      await page.getByRole('button', { name: 'Add Date Range' }).first().click()
      await expect(page.getByRole('dialog')).toBeVisible()
      // Pick dates in the visible months (Feb/Mar 2026)
      await page.getByTestId('calendar-day-2026-03-10').click()
      await page.getByTestId('calendar-day-2026-03-15').click()
      await expect(page.getByRole('dialog')).not.toBeVisible()

      // Verify date range appeared
      const dateRangeItems = page.getByTestId('date-range-item')
      await expect(dateRangeItems).toHaveCount(1)

      // 4. Add a second date range (preselected 7 days after first: Mar 17-22)
      await page.getByRole('button', { name: 'Add Date Range' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page.getByTestId('calendar-day-2026-03-20').click()
      await page.getByTestId('calendar-day-2026-03-25').click()
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
