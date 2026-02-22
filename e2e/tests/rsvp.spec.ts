import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getTestSession,
  setupAuthenticatedPage,
  createEventWithPoll,
  createResolvedEvent,
  getObjectsByType,
  PAGE_LOAD_TIMEOUT,
} from '../helpers'

const TEST_EMAIL = 'e2e-rsvp@example.com'
const TEST_NAME = 'E2E RSVP User'

test.describe('RSVP Feature', () => {
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

      await page.goto(`/events/${eventId}`)
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

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('rsvp-section')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // First attend
      await page.getByTestId('rsvp-attend').click()
      await expect(page.getByTestId('rsvp-attend')).toHaveClass(/bg-green-600/)

      // Then decline
      await page.getByTestId('rsvp-decline').click()
      await expect(page.getByTestId('rsvp-decline')).toHaveClass(/bg-red-600/)
      // Attend button should no longer be active
      await expect(page.getByTestId('rsvp-attend')).not.toHaveClass(
        /bg-green-600/
      )
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
      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('rsvp-section')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // User should be auto-RSVPed as attending
      await expect(page.getByTestId('rsvp-attend')).toHaveClass(/bg-green-600/)
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
