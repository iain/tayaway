import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getObjectByType,
  getObjectsByType,
  getTestSession,
  setupAuthenticatedPage,
  createEventWithPoll,
  addMemberToWorkspace,
  PAGE_LOAD_TIMEOUT,
  newApiContext,
  offsetDate,
} from '../helpers'

const TEST_EMAIL = 'e2e-voting@example.com'
const TEST_EMAIL_2 = 'e2e-voting-2@example.com'
const TEST_NAME = 'E2E Voting User'
const TEST_NAME_2 = 'E2E Voting User 2'

test.describe('Voting Feature', () => {
  test.describe('Votes API - Unauthenticated', () => {
    test('all votes endpoints require auth', async ({ request }) => {
      const responses = await Promise.all([
        request.get(`${API_BASE}/api/events/some-id/votes`),
        request.post(`${API_BASE}/api/events/some-id/votes`, {
          data: { date_range_id: 'some-id', response: 'yes' },
        }),
        request.delete(`${API_BASE}/api/events/some-id/votes/some-vote-id`),
      ])
      for (const response of responses) {
        expect(response.status()).toBe(401)
        const body = await response.json()
        expect(body.error).toBe('Authorization required')
      }
    })
  })

  test.describe('Votes API - Authenticated', () => {
    let apiContext: APIRequestContext

    test.beforeAll(async ({ playwright }) => {
      apiContext = await newApiContext(playwright)
      await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('POST /api/events/:id/votes creates a vote', async () => {
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      const response = await apiContext.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          data: {
            date_range_id: dateRangeId,
            response: 'yes',
            comment: 'This date works great!',
          },
        }
      )

      expect(response.status()).toBe(201)
      const body = await response.json()
      const vote = getObjectByType(body.objects, 'vote')
      expect(vote).toHaveProperty('id')
      expect(vote?.response).toBe('yes')
      expect(vote?.comment).toBe('This date works great!')
      expect(vote?.dateRangeId).toBe(dateRangeId)
    })

    test('POST /api/events/:id/votes updates existing vote', async () => {
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      // Create initial vote
      await apiContext.post(`${API_BASE}/api/events/${eventId}/votes`, {
        data: {
          date_range_id: dateRangeId,
          response: 'yes',
        },
      })

      // Update to different response
      const response = await apiContext.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          data: {
            date_range_id: dateRangeId,
            response: 'no',
            comment: 'Changed my mind',
          },
        }
      )

      expect(response.status()).toBe(200)
      const body = await response.json()
      const vote = getObjectByType(body.objects, 'vote')
      expect(vote?.response).toBe('no')
      expect(vote?.comment).toBe('Changed my mind')
    })

    test('POST /api/events/:id/votes validates required fields and response value', async () => {
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      // Missing date_range_id
      const missingDrResponse = await apiContext.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        { data: { response: 'yes' } }
      )
      expect(missingDrResponse.status()).toBe(400)
      const missingDrBody = await missingDrResponse.json()
      expect(missingDrBody.error).toBe('date_range_id is required')

      // Missing response
      const missingRespResponse = await apiContext.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        { data: { date_range_id: dateRangeId } }
      )
      expect(missingRespResponse.status()).toBe(400)
      const missingRespBody = await missingRespResponse.json()
      expect(missingRespBody.error).toBe('response is required')

      // Invalid response value
      const invalidResponse = await apiContext.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          data: {
            date_range_id: dateRangeId,
            response: 'invalid_response',
          },
        }
      )
      expect(invalidResponse.status()).toBe(400)
      const invalidBody = await invalidResponse.json()
      expect(invalidBody.error).toBe('Invalid response value')
    })

    test('POST /api/events/:id/votes rejects date_range from different event', async () => {
      const { dateRangeId } = await createEventWithPoll(apiContext)
      const { eventId: otherEventId } = await createEventWithPoll(apiContext)

      const response = await apiContext.post(
        `${API_BASE}/api/events/${otherEventId}/votes`,
        {
          data: {
            date_range_id: dateRangeId,
            response: 'yes',
          },
        }
      )

      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('Date range does not belong to this event')
    })

    test('GET /api/events/:id/votes returns all votes for event', async () => {
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      // Create a vote
      await apiContext.post(`${API_BASE}/api/events/${eventId}/votes`, {
        data: {
          date_range_id: dateRangeId,
          response: 'yes',
        },
      })

      const response = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/votes`
      )

      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const votes = getObjectsByType(body.objects, 'vote')
      expect(votes).toHaveLength(1)
      expect(votes[0]?.response).toBe('yes')
    })

    test('DELETE /api/events/:id/votes/:vote_id removes vote', async () => {
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      // Create a vote
      const createResponse = await apiContext.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          data: {
            date_range_id: dateRangeId,
            response: 'yes',
          },
        }
      )
      const createBody = await createResponse.json()
      const vote = getObjectByType(createBody.objects, 'vote')

      // Delete the vote
      const deleteResponse = await apiContext.delete(
        `${API_BASE}/api/events/${eventId}/votes/${vote!.id}`
      )

      expect(deleteResponse.ok()).toBeTruthy()
      const body = await deleteResponse.json()
      expect(body.deleted).toHaveLength(1)
      expect(body.deleted[0].objectType).toBe('vote')
      expect(body.deleted[0].id).toBe(vote!.id)

      // Verify vote is gone
      const getResponse = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/votes`
      )
      const getBody = await getResponse.json()
      const votes = getObjectsByType(getBody.objects, 'vote')
      expect(votes).toHaveLength(0)
    })

    test('DELETE /api/events/:id/votes/:vote_id returns 403 for other user vote', async ({
      playwright,
    }) => {
      // User 1 creates event and votes via shared apiContext
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      const createResponse = await apiContext.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          data: {
            date_range_id: dateRangeId,
            response: 'yes',
          },
        }
      )
      const createBody = await createResponse.json()
      const vote = getObjectByType(createBody.objects, 'vote')

      // User 2 on separate request context
      const user2Request = await newApiContext(playwright)
      await getTestSession(user2Request, TEST_EMAIL_2, TEST_NAME_2)

      // User 2 tries to delete User 1's vote
      const deleteResponse = await user2Request.delete(
        `${API_BASE}/api/events/${eventId}/votes/${vote!.id}`
      )

      expect(deleteResponse.status()).toBe(403)
      const body = await deleteResponse.json()
      expect(body.error).toBe('Access denied')

      await user2Request.dispose()
    })

    test('event includes votes in response', async () => {
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      // Create a vote
      await apiContext.post(`${API_BASE}/api/events/${eventId}/votes`, {
        data: {
          date_range_id: dateRangeId,
          response: 'preferably_not',
          comment: 'I can make it work',
        },
      })

      // GET /api/events/:id returns only the event (no cascade)
      const eventResponse = await apiContext.get(
        `${API_BASE}/api/events/${eventId}`
      )
      const eventBody = await eventResponse.json()
      const events = getObjectsByType(eventBody.objects, 'event')
      expect(events).toHaveLength(1)
      expect(events[0]?.id).toBe(eventId)

      // Votes are fetched separately via GET /api/events/:id/votes
      const votesResponse = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/votes`
      )
      const votesBody = await votesResponse.json()
      const votes = getObjectsByType(votesBody.objects, 'vote')
      expect(votes).toHaveLength(1)
      expect(votes[0]?.response).toBe('preferably_not')
    })

    test('non-workspace-member cannot view event', async ({ playwright }) => {
      // Owner creates event via shared apiContext
      const { eventId } = await createEventWithPoll(apiContext)

      // Other user on separate request context
      const user2Request = await newApiContext(playwright)
      await getTestSession(user2Request, TEST_EMAIL_2, TEST_NAME_2)

      // Other user (not in workspace) cannot view the event
      const response = await user2Request.get(
        `${API_BASE}/api/events/${eventId}`
      )

      expect(response.status()).toBe(403)
      const body = await response.json()
      expect(body.error).toBe('Access denied')

      await user2Request.dispose()
    })

    test('non-workspace-member cannot vote on event', async ({
      playwright,
    }) => {
      // Owner creates event via shared apiContext
      const { eventId, dateRangeId } = await createEventWithPoll(apiContext)

      // Other user on separate request context
      const user2Request = await newApiContext(playwright)
      await getTestSession(user2Request, TEST_EMAIL_2, TEST_NAME_2)

      // Other user (not in workspace) cannot vote on the event
      const response = await user2Request.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          data: {
            date_range_id: dateRangeId,
            response: 'yes',
          },
        }
      )

      expect(response.status()).toBe(403)
      const body = await response.json()
      expect(body.error).toBe('Access denied')

      await user2Request.dispose()
    })
  })

  test.describe('Date Poll API', () => {
    let apiContext: APIRequestContext

    test.beforeAll(async ({ playwright }) => {
      apiContext = await newApiContext(playwright)
      await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('poll lifecycle: create, close with winner, vote fails on closed, reopen', async () => {
      // --- Create poll on a bare event ---
      const eventResponse = await apiContext.post(`${API_BASE}/api/events`, {
        data: { name: 'Poll Test Event' },
      })
      const eventBody = await eventResponse.json()
      const event = getObjectByType(eventBody.objects, 'event')

      const deadline = new Date(
        Date.now() + 7 * 24 * 60 * 60 * 1000
      ).toISOString()
      const pollResponse = await apiContext.post(
        `${API_BASE}/api/events/${event!.id}/poll`,
        { data: { deadline } }
      )

      expect(pollResponse.status()).toBe(201)
      const pollBody = await pollResponse.json()
      const createdPoll = getObjectByType(pollBody.objects, 'datePoll')
      expect(createdPoll).toHaveProperty('id')
      expect(createdPoll?.status).toBe('open')

      // Add a date range so we can close with a winner
      const drResponse = await apiContext.post(
        `${API_BASE}/api/events/${event!.id}/poll/date-ranges`,
        { data: { start_date: offsetDate(14), end_date: offsetDate(20) } }
      )
      const drBody = await drResponse.json()
      const dateRange = getObjectByType(drBody.objects, 'dateRange')

      // --- Close poll with winner ---
      const closeResponse = await apiContext.post(
        `${API_BASE}/api/events/${event!.id}/poll/close`,
        { data: { selected_date_range_id: dateRange!.id } }
      )

      expect(closeResponse.ok()).toBeTruthy()
      const closeBody = await closeResponse.json()
      const closedPoll = getObjectByType(closeBody.objects, 'datePoll')
      expect(closedPoll?.status).toBe('resolved')
      expect(closedPoll?.selectedDateRangeId).toBe(dateRange!.id)

      // --- Voting fails on closed poll ---
      const voteResponse = await apiContext.post(
        `${API_BASE}/api/events/${event!.id}/votes`,
        {
          data: {
            date_range_id: dateRange!.id,
            response: 'yes',
          },
        }
      )

      expect(voteResponse.status()).toBe(400)
      const voteBody = await voteResponse.json()
      expect(voteBody.error).toBe('Poll is not open for voting')

      // --- Reopen poll ---
      const newDeadline = new Date(
        Date.now() + 14 * 24 * 60 * 60 * 1000
      ).toISOString()
      const reopenResponse = await apiContext.post(
        `${API_BASE}/api/events/${event!.id}/poll/reopen`,
        { data: { deadline: newDeadline } }
      )

      expect(reopenResponse.ok()).toBeTruthy()
      const reopenBody = await reopenResponse.json()
      const reopenedPoll = getObjectByType(reopenBody.objects, 'datePoll')
      expect(reopenedPoll?.status).toBe('open')
      expect(reopenedPoll?.selectedDateRangeId).toBeNull()
    })
  })

  test.describe('Votes UI', () => {
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

    test('can navigate to event, vote, change vote, and expand voters list', async ({
      page,
    }) => {
      const { eventId } = await createEventWithPoll(
        apiContext,
        'Voting Test Event'
      )
      await setupAuthenticatedPage(page, sessionToken)

      // --- Navigate to event from events list ---
      await page.goto('/events')
      await expect(page.getByText('Voting Test Event').first()).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await page.getByText('Voting Test Event').first().click()

      // Verify we're on an event detail page (URL contains /events/ followed by a UUID)
      await expect(page).toHaveURL(/\/events\/[0-9a-f-]+$/)
      await expect(page.getByTestId('event-name')).toContainText(
        'Voting Test Event'
      )

      // --- Navigate to vote page and verify buttons ---
      await page.goto(`/events/${eventId}/planning/vote`)

      // Should see vote buttons
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
      await expect(
        page
          .getByRole('button', { name: 'Preferably not', exact: true })
          .first()
      ).toBeVisible()
      await expect(
        page.getByRole('button', { name: 'No', exact: true }).first()
      ).toBeVisible()

      // --- Vote Yes on first date range ---
      await page
        .getByRole('button', { name: 'Yes', exact: true })
        .first()
        .click()

      // Button should now be highlighted (active state)
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).toHaveAttribute('aria-pressed', 'true')

      // Vote summary should show 1 yes
      await expect(page.getByTestId('vote-summary').first()).toContainText(
        '1 yes'
      )

      // --- Change vote to No ---
      await page
        .getByRole('button', { name: 'No', exact: true })
        .first()
        .click()
      await expect(
        page.getByRole('button', { name: 'No', exact: true }).first()
      ).toHaveAttribute('aria-pressed', 'true')
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).toHaveAttribute('aria-pressed', 'false')

      // Vote summary should now show 1 no
      await expect(page.getByTestId('vote-summary').first()).toContainText(
        '1 no'
      )

      // --- Expand voters list ---
      await page
        .getByRole('button', { name: /Show votes/ })
        .first()
        .click()

      // Should see the voter
      await expect(page.getByText(TEST_NAME).first()).toBeVisible()
    })

    test('back button returns to events list', async ({ page }) => {
      const { eventId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await page.getByRole('link', { name: 'Events' }).first().click()

      await expect(page).toHaveURL('/events')
    })

    test('event page shows new user in awaiting votes section', async ({
      page,
      playwright,
    }) => {
      const { eventId, workspaceId } = await createEventWithPoll(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      // Navigate to the event planning page
      await page.goto(`/events/${eventId}/planning`)

      // Wait for the event name to be visible (indicates page is loaded)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // The votes section should show initially (just the creator)
      const awaitingSection = page.getByTestId('awaiting-votes-section')
      await expect(page.getByRole('heading', { name: 'Votes' })).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Now add a new member via test API (simulating another tab/user adding someone)
      const newUserName = `New User ${Date.now()}`
      const newUserEmail = `new-user-${Date.now()}@example.com`
      // Create the user first via test session, then add as member
      const newUserContext = await newApiContext(playwright)
      await getTestSession(newUserContext, newUserEmail, newUserName)
      await addMemberToWorkspace(apiContext, workspaceId, newUserEmail)
      await newUserContext.dispose()

      // The new member should appear in real-time via WebSocket (no page refresh)
      await expect(awaitingSection.getByText(newUserName)).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Should show count of people who haven't voted
      await expect(
        awaitingSection.getByText(/haven't fully voted yet/)
      ).toBeVisible()
    })
  })
})
