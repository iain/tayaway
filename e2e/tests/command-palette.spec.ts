import { test, expect, APIRequestContext, Page } from '@playwright/test'
import {
  PAGE_LOAD_TIMEOUT,
  getTestSession,
  setupAuthenticatedPage,
  createBareEvent,
  createEventWithPoll,
  createResolvedEvent,
  newApiContext,
} from '../helpers'

const TEST_EMAIL = 'e2e-command-palette@example.com'
const TEST_NAME = 'E2E Command Palette User'

/** Open the command palette via keyboard and wait for the search input. */
async function openPalette(page: Page) {
  // Click body to ensure page focus (Ctrl+K may be intercepted by the browser
  // address bar if focus is outside the page content area).
  await page.locator('body').click()
  await page.keyboard.press('Control+k')
  await expect(page.getByPlaceholder('Search...')).toBeVisible()
}

test.describe('Command Palette', () => {
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

  test.describe('Global behavior', () => {
    test('opens with Ctrl+K and shows Navigation section', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/')

      await expect(page.getByTestId('page-title')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await openPalette(page)

      const dialog = page.getByRole('dialog')

      // Shows Navigation heading
      await expect(
        dialog.getByText('Navigation', { exact: true })
      ).toBeVisible()

      // Shows standard nav items
      await expect(dialog.getByText('Dashboard')).toBeVisible()
      await expect(dialog.getByText('Events')).toBeVisible()
    })

    test('closes with Escape', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/')

      await expect(page.getByTestId('page-title')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await openPalette(page)

      await page.keyboard.press('Escape')
      await expect(page.getByPlaceholder('Search...')).not.toBeVisible()
    })

    test('search filters Navigation items', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/')

      await expect(page.getByTestId('page-title')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await openPalette(page)
      await page.getByPlaceholder('Search...').fill('settings')

      const dialog = page.getByRole('dialog')

      // Filtered result shows matching item. Exact: "settings" also matches
      // the per-workspace settings entries.
      await expect(dialog.getByText('Settings', { exact: true })).toBeVisible()

      // Non-matching items are hidden
      await expect(dialog.getByText('Dashboard')).not.toBeVisible()
    })

    test('selecting a Navigation item navigates', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/')

      await expect(page.getByTestId('page-title')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await openPalette(page)
      await page.getByPlaceholder('Search...').fill('settings')

      await page
        .getByRole('dialog')
        .getByText('Settings', { exact: true })
        .click()
      await expect(page.getByPlaceholder('Search...')).not.toBeVisible()
      await expect(page).toHaveURL('/settings/profile')
    })
  })

  test.describe('Event context commands', () => {
    test('shows contextual commands on event overview page', async ({
      page,
    }) => {
      const eventId = await createBareEvent(
        apiContext,
        'Palette Overview Event'
      )

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}`)

      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await openPalette(page)
      const dialog = page.getByRole('dialog')

      // Shows navigation commands for other sections
      await expect(dialog.getByText('Go to Planning')).toBeVisible()
      await expect(dialog.getByText('Go to RSVP')).toBeVisible()
      await expect(dialog.getByText('Go to Expenses')).toBeVisible()

      // Does NOT show "Go to <event name>" since we're on the overview
      await expect(
        dialog.getByText('Go to Palette Overview Event')
      ).not.toBeVisible()
    })

    test('excludes current page from contextual commands', async ({ page }) => {
      const eventId = await createBareEvent(apiContext, 'Palette Exclude Event')

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/rsvp`)

      await expect(page.getByRole('link', { name: 'RSVP' })).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await openPalette(page)
      const dialog = page.getByRole('dialog')

      // On RSVP page, so "Go to RSVP" should be excluded
      await expect(dialog.getByText('Go to RSVP')).not.toBeVisible()

      // But other commands should show
      await expect(
        dialog.getByText('Go to Palette Exclude Event')
      ).toBeVisible()
      await expect(dialog.getByText('Go to Planning')).toBeVisible()
      await expect(dialog.getByText('Go to Expenses')).toBeVisible()
    })

    test('shows vote and date range commands for active poll', async ({
      page,
    }) => {
      const { eventId } = await createEventWithPoll(
        apiContext,
        'Palette Poll Event'
      )

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}`)

      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await openPalette(page)
      const dialog = page.getByRole('dialog')

      // Active poll with date ranges should show vote command
      await expect(dialog.getByText('Vote on dates')).toBeVisible()
      await expect(dialog.getByText('Add date options')).toBeVisible()
    })

    test('shows download calendar and add expense for resolved event', async ({
      page,
    }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Palette Resolved Event'
      )

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}`)

      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await openPalette(page)
      const dialog = page.getByRole('dialog')

      // Resolved event has dates, so calendar download and expense should show
      await expect(dialog.getByText('Download calendar file')).toBeVisible()
      await expect(dialog.getByText('Add expense')).toBeVisible()

      // Resolved poll is not active, so no vote/date-range commands
      await expect(dialog.getByText('Vote on dates')).not.toBeVisible()
      await expect(dialog.getByText('Add date options')).not.toBeVisible()
    })

    test('searching filters contextual commands', async ({ page }) => {
      const { eventId } = await createEventWithPoll(
        apiContext,
        'Palette Search Event'
      )

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}`)

      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await openPalette(page)
      await page.getByPlaceholder('Search...').fill('vote')

      const dialog = page.getByRole('dialog')

      // "Vote on dates" matches the search
      await expect(dialog.getByText('Vote on dates')).toBeVisible()

      // Non-matching context commands are hidden
      await expect(dialog.getByText('Go to Planning')).not.toBeVisible()
      await expect(dialog.getByText('Go to RSVP')).not.toBeVisible()
    })

    test('selecting a contextual command navigates to the correct page', async ({
      page,
    }) => {
      const eventId = await createBareEvent(
        apiContext,
        'Palette Navigate Event'
      )

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}`)

      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await openPalette(page)
      await page.getByRole('dialog').getByText('Go to RSVP').click()

      await expect(page.getByPlaceholder('Search...')).not.toBeVisible()
      await expect(page).toHaveURL(`/events/${eventId}/rsvp`)
    })

    // Leaving an event no longer leaves event mode: the subheader keeps
    // naming the focused event on workspace pages, so the palette has to
    // agree with it rather than going silent about the event the chrome is
    // still pointing at.
    test('context commands follow the focused event onto workspace pages', async ({
      page,
    }) => {
      const eventId = await createBareEvent(
        apiContext,
        'Palette Disappear Event'
      )

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}`)

      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Verify context commands exist on event page
      await openPalette(page)
      await expect(
        page.getByRole('dialog').getByText('Go to Planning')
      ).toBeVisible()
      await page.keyboard.press('Escape')
      await expect(page.getByPlaceholder('Search...')).not.toBeVisible()

      // Navigate to dashboard — opening the event focused it, so it stays
      // the event both the bar and the palette are about.
      await page.goto('/')
      await expect(page.getByTestId('page-title')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await openPalette(page)
      await expect(
        page.getByRole('dialog').getByText('Go to Planning')
      ).toBeVisible()
      await expect(
        page.getByRole('dialog').getByText('Navigation', { exact: true })
      ).toBeVisible()
    })
  })
})
