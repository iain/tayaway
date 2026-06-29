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

      await page.goto(`/events/${eventId}/planning`)
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

      await page.goto(`/events/${eventId}/planning`)
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
      await page.goto(`/events/${eventId}/planning`)

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
      await page.goto(`/events/${eventId}/planning`)
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
      await page.goto(`/events/${eventId}/planning`)
      await expect(page.getByTestId('rsvp-section')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      const otherRow = page.locator('li').filter({ hasText: OTHER_NAME })
      await expect(otherRow).toBeVisible()

      await otherRow.getByTestId('rsvp-other-menu').click()

      const [postResponse] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes(`/api/events/${eventId}/rsvps`) &&
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
      const rsvpsResp = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/rsvps`
      )
      const rsvpsBody = await rsvpsResp.json()
      const rsvps = getObjectsByType(rsvpsBody.objects, 'rsvp') as Array<{
        userId: string
        attending: boolean
        createdByUserId: string | null
      }>
      const onBehalf = rsvps.find((r) => r.userId === otherUserId)
      expect(onBehalf).toBeDefined()
      expect(onBehalf!.attending).toBe(true)
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
      const rsvps = getObjectsByType(closeBody.objects, 'rsvp')

      expect(rsvps.length).toBe(1)
      expect(rsvps[0]!.attending).toBe(true)
    })

    test('poll reopen deletes RSVPs', async () => {
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      // Vote + close
      await apiContext.post(`${API_BASE}/api/events/${eventId}/votes`, {
        data: { date_range_id: dateRangeId, response: 'yes' },
      })
      await apiContext.post(`${API_BASE}/api/events/${eventId}/poll/close`, {
        data: { selected_date_range_id: dateRangeId },
      })

      // Verify RSVP exists
      const rsvpResponse = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/rsvps`
      )
      const rsvpBody = await rsvpResponse.json()
      const rsvpsBefore = getObjectsByType(rsvpBody.objects, 'rsvp')
      expect(rsvpsBefore.length).toBe(1)

      // Reopen poll
      const deadline = new Date(
        Date.now() + 7 * 24 * 60 * 60 * 1000
      ).toISOString()
      const reopenResponse = await apiContext.post(
        `${API_BASE}/api/events/${eventId}/poll/reopen`,
        { data: { deadline } }
      )
      const reopenBody = await reopenResponse.json()

      // RSVPs should be in deleted list
      expect(reopenBody.deleted.length).toBeGreaterThan(0)
      expect(reopenBody.deleted[0].objectType).toBe('rsvp')

      // Verify no RSVPs remain
      const rsvpResponse2 = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/rsvps`
      )
      const rsvpBody2 = await rsvpResponse2.json()
      const rsvpsAfter = getObjectsByType(rsvpBody2.objects, 'rsvp')
      expect(rsvpsAfter.length).toBe(0)
    })
  })
})
