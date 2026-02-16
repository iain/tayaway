import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getTestSession,
  setupAuthenticatedPage,
  createBareEvent,
  createEventWithPoll,
  createResolvedEvent,
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
    test('event page shows "Open Date Poll" button when no poll exists', async ({
      page,
    }) => {
      const eventId = await createBareEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

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
    }) => {
      const eventId = await createBareEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

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

    test('can open a date poll through the modal', async ({ page }) => {
      const eventId = await createBareEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

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
    test('clicking "Add Date Range" opens calendar modal', async ({ page }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

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
    }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

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

    test('can remove a date range', async ({ page }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

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
    let openEventId: string
    let resolvedEventId: string

    test.beforeAll(async () => {
      const { eventId: eid1 } = await createEventWithPoll(apiContext)
      openEventId = eid1
      const { eventId: eid2 } = await createResolvedEvent(apiContext)
      resolvedEventId = eid2
    })

    test('open poll shows remaining time', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${openEventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      // Should show time remaining
      await expect(page.getByText(/remaining/)).toBeVisible({ timeout: 5000 })
    })

    test('open poll shows "Vote on Dates" button', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${openEventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      await expect(
        page.getByRole('button', { name: 'Vote on Dates' })
      ).toBeVisible({ timeout: 5000 })
    })

    test('resolved poll shows winner badge', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${resolvedEventId}`)
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
    test('"Select Winner" button opens close poll modal', async ({ page }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

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

    test('can select a winner and close the poll', async ({ page }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

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

    test('closing a poll populates event dates from winning date range', async ({
      page,
    }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      // Event should not show dates before poll is closed
      await expect(page.getByTestId('event-dates')).not.toBeVisible()

      // Close the poll by selecting the first date range (Jun 1-7)
      await page.getByRole('button', { name: 'Select Winner' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page.getByRole('dialog').locator('button.w-full').first().click()
      await page.getByRole('button', { name: 'Confirm Winner' }).click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      // Event header should now show dates from the winning date range
      await expect(page.getByTestId('event-dates')).toBeVisible({
        timeout: 5000,
      })
      await expect(page.getByTestId('event-dates')).toContainText(/Jun/)
    })
  })

  test.describe('Reopening a poll', () => {
    test('"Reopen Poll" button is visible on resolved poll', async ({
      page,
    }) => {
      const { eventId } = await createResolvedEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

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
    }) => {
      const { eventId } = await createResolvedEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

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

    test('can reopen a resolved poll', async ({ page }) => {
      const { eventId } = await createResolvedEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

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

    test('reopening a poll clears event dates', async ({ page }) => {
      const { eventId } = await createResolvedEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      // Resolved event should show dates from winning date range (Jun 1-7)
      await expect(page.getByTestId('event-dates')).toBeVisible({
        timeout: 5000,
      })
      await expect(page.getByTestId('event-dates')).toContainText(/Jun/)

      // Reopen the poll
      await page.getByRole('button', { name: 'Reopen Poll' }).click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await page.getByRole('button', { name: 'Open Poll', exact: true }).click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      // Event dates should be cleared
      await expect(page.getByTestId('event-dates')).not.toBeVisible({
        timeout: 5000,
      })
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

      await page.goto(`/events/${resolvedEventId}/vote`)

      await expect(page.getByText('Voting is closed')).toBeVisible({
        timeout: 10000,
      })
      await expect(
        page.getByText('The date poll is no longer accepting votes.')
      ).toBeVisible()
    })

    test('"Vote on Dates" button navigates to vote page', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${openEventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      await page
        .getByRole('button', { name: 'Vote on Dates' })
        .click({ timeout: 5000 })

      await expect(page).toHaveURL(`/events/${openEventId}/vote`)
      // Should see voting cards for each date range
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).toBeVisible({ timeout: 5000 })
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
