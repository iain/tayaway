import { test, expect, APIRequestContext } from '@playwright/test'
import {
  getTestSession,
  setupAuthenticatedPage,
  createEventWithPoll,
  createResolvedEvent,
  PAGE_LOAD_TIMEOUT,
  newApiContext,
} from '../helpers'

const TEST_EMAIL = 'e2e-dates-tab@example.com'
const TEST_NAME = 'E2E Dates Tab User'

// The planning and RSVP pages were merged into a single phase-driven "Dates"
// tab: it shows the date poll while voting and the RSVP list once dates are
// confirmed. These tests pin that single-tab contract and the /rsvp redirect.
test.describe('Merged Dates tab', () => {
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

  test('subheader has a single "Dates" tab, not Planning/RSVP', async ({
    page,
  }) => {
    const { eventId } = await createEventWithPoll(apiContext)
    await setupAuthenticatedPage(page, sessionToken)

    await page.goto(`/events/${eventId}/planning`)
    await expect(page.getByTestId('event-name')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    await expect(
      page.getByRole('link', { name: 'Dates', exact: true })
    ).toBeVisible()
    await expect(
      page.getByRole('link', { name: 'Planning', exact: true })
    ).toHaveCount(0)
    await expect(
      page.getByRole('link', { name: 'RSVP', exact: true })
    ).toHaveCount(0)
  })

  test('/rsvp redirects to /planning', async ({ page }) => {
    const { eventId } = await createResolvedEvent(apiContext)
    await setupAuthenticatedPage(page, sessionToken)

    await page.goto(`/events/${eventId}/rsvp`)
    await expect(page).toHaveURL(`/events/${eventId}/planning`)
  })

  test('an open poll shows the date poll on the Dates tab', async ({ page }) => {
    const { eventId } = await createEventWithPoll(apiContext)
    await setupAuthenticatedPage(page, sessionToken)

    await page.goto(`/events/${eventId}/planning`)
    await expect(
      page.getByRole('button', { name: 'Vote on Dates' })
    ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
    await expect(page.getByTestId('rsvp-section')).not.toBeVisible()
  })

  test('a resolved event shows the RSVP section on the Dates tab', async ({
    page,
  }) => {
    const { eventId } = await createResolvedEvent(apiContext)
    await setupAuthenticatedPage(page, sessionToken)

    await page.goto(`/events/${eventId}/planning`)
    await expect(page.getByTestId('rsvp-section')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
  })
})
