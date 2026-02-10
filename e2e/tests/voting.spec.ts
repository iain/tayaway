import { test, expect, Page, APIRequestContext } from '@playwright/test'

const API_BASE = 'http://localhost:9293'
const TEST_EMAIL = 'e2e-voting@example.com'
const TEST_EMAIL_2 = 'e2e-voting-2@example.com'
const TEST_NAME = 'E2E Voting User'
const TEST_NAME_2 = 'E2E Voting User 2'

// Helper to extract objects from pool response by type
interface PoolObject {
  id: string
  objectType: string
  [key: string]: unknown
}

function getObjectsByType<T extends PoolObject>(
  objects: PoolObject[],
  type: string
): T[] {
  return objects.filter((o) => o.objectType === type) as T[]
}

function getObjectByType<T extends PoolObject>(
  objects: PoolObject[],
  type: string
): T | undefined {
  return objects.find((o) => o.objectType === type) as T | undefined
}

// Helper to get an authenticated session for testing
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

// Helper to make authenticated API requests
function authHeaders(token: string): { Authorization: string } {
  return { Authorization: `Bearer ${token}` }
}

// Helper to set up authenticated page
async function setupAuthenticatedPage(
  page: Page,
  token: string
): Promise<void> {
  await page.goto('/')
  await page.evaluate((t) => {
    localStorage.setItem('session_token', t)
  }, token)
}

// Helper to create an event with a date poll and date ranges
async function createTestEvent(
  request: APIRequestContext,
  token: string
): Promise<{ eventId: string; dateRangeId: string }> {
  // 1. Create the event
  const eventResponse = await request.post(`${API_BASE}/api/events`, {
    headers: authHeaders(token),
    data: {
      name: 'Voting Test Event',
      description: 'An event for testing voting',
    },
  })
  const eventBody = await eventResponse.json()
  const event = getObjectByType(eventBody.objects, 'event')
  const eventId = event!.id

  // 2. Open a date poll
  const deadline = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()
  await request.post(`${API_BASE}/api/events/${eventId}/poll`, {
    headers: authHeaders(token),
    data: { deadline },
  })

  // 3. Add date ranges
  const dr1Response = await request.post(
    `${API_BASE}/api/events/${eventId}/poll/date-ranges`,
    {
      headers: authHeaders(token),
      data: { start_date: '2025-06-01', end_date: '2025-06-07' },
    }
  )
  const dr1Body = await dr1Response.json()
  const dateRange1 = getObjectByType(dr1Body.objects, 'dateRange')

  await request.post(`${API_BASE}/api/events/${eventId}/poll/date-ranges`, {
    headers: authHeaders(token),
    data: { start_date: '2025-06-15', end_date: '2025-06-20' },
  })

  return {
    eventId,
    dateRangeId: dateRange1!.id,
  }
}

test.describe('Voting Feature', () => {
  test.describe('Votes API - Unauthenticated', () => {
    test('GET /api/events/:id/votes returns 401 without auth', async ({
      request,
    }) => {
      const response = await request.get(`${API_BASE}/api/events/some-id/votes`)
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })

    test('POST /api/events/:id/votes returns 401 without auth', async ({
      request,
    }) => {
      const response = await request.post(
        `${API_BASE}/api/events/some-id/votes`,
        {
          data: { date_range_id: 'some-id', response: 'yes' },
        }
      )
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })

    test('DELETE /api/events/:id/votes/:vote_id returns 401 without auth', async ({
      request,
    }) => {
      const response = await request.delete(
        `${API_BASE}/api/events/some-id/votes/some-vote-id`
      )
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })
  })

  test.describe('Votes API - Authenticated', () => {
    test('POST /api/events/:id/votes creates a vote', async ({ request }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      const response = await request.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          headers: authHeaders(token),
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

    test('POST /api/events/:id/votes updates existing vote', async ({
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      // Create initial vote
      await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token),
        data: {
          date_range_id: dateRangeId,
          response: 'yes',
        },
      })

      // Update to different response
      const response = await request.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          headers: authHeaders(token),
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

    test('POST /api/events/:id/votes validates response value', async ({
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      const response = await request.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          headers: authHeaders(token),
          data: {
            date_range_id: dateRangeId,
            response: 'invalid_response',
          },
        }
      )

      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('Invalid response value')
    })

    test('POST /api/events/:id/votes requires date_range_id', async ({
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)

      const response = await request.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          headers: authHeaders(token),
          data: { response: 'yes' },
        }
      )

      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('date_range_id is required')
    })

    test('POST /api/events/:id/votes requires response', async ({
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      const response = await request.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          headers: authHeaders(token),
          data: { date_range_id: dateRangeId },
        }
      )

      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('response is required')
    })

    test('POST /api/events/:id/votes rejects date_range from different event', async ({
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { dateRangeId } = await createTestEvent(request, token)
      const { eventId: otherEventId } = await createTestEvent(request, token)

      const response = await request.post(
        `${API_BASE}/api/events/${otherEventId}/votes`,
        {
          headers: authHeaders(token),
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

    test('GET /api/events/:id/votes returns all votes for event', async ({
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      // Create a vote
      await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token),
        data: {
          date_range_id: dateRangeId,
          response: 'yes',
        },
      })

      const response = await request.get(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          headers: authHeaders(token),
        }
      )

      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const votes = getObjectsByType(body.objects, 'vote')
      expect(votes).toHaveLength(1)
      expect(votes[0]?.response).toBe('yes')
    })

    test('DELETE /api/events/:id/votes/:vote_id removes vote', async ({
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      // Create a vote
      const createResponse = await request.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          headers: authHeaders(token),
          data: {
            date_range_id: dateRangeId,
            response: 'yes',
          },
        }
      )
      const createBody = await createResponse.json()
      const vote = getObjectByType(createBody.objects, 'vote')

      // Delete the vote
      const deleteResponse = await request.delete(
        `${API_BASE}/api/events/${eventId}/votes/${vote!.id}`,
        {
          headers: authHeaders(token),
        }
      )

      expect(deleteResponse.ok()).toBeTruthy()
      const body = await deleteResponse.json()
      expect(body.deleted).toHaveLength(1)
      expect(body.deleted[0].objectType).toBe('vote')
      expect(body.deleted[0].id).toBe(vote!.id)

      // Verify vote is gone
      const getResponse = await request.get(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          headers: authHeaders(token),
        }
      )
      const getBody = await getResponse.json()
      const votes = getObjectsByType(getBody.objects, 'vote')
      expect(votes).toHaveLength(0)
    })

    test('DELETE /api/events/:id/votes/:vote_id returns 403 for other user vote', async ({
      request,
    }) => {
      const { token: token1 } = await getTestSession(
        request,
        TEST_EMAIL,
        TEST_NAME
      )
      const { token: token2 } = await getTestSession(
        request,
        TEST_EMAIL_2,
        TEST_NAME_2
      )
      const { eventId, dateRangeId } = await createTestEvent(request, token1)

      // User 1 creates a vote
      const createResponse = await request.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          headers: authHeaders(token1),
          data: {
            date_range_id: dateRangeId,
            response: 'yes',
          },
        }
      )
      const createBody = await createResponse.json()
      const vote = getObjectByType(createBody.objects, 'vote')

      // User 2 tries to delete User 1's vote
      const deleteResponse = await request.delete(
        `${API_BASE}/api/events/${eventId}/votes/${vote!.id}`,
        {
          headers: authHeaders(token2),
        }
      )

      expect(deleteResponse.status()).toBe(403)
      const body = await deleteResponse.json()
      expect(body.error).toBe('Access denied')
    })

    test('event includes votes in response', async ({ request }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      // Create a vote
      await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token),
        data: {
          date_range_id: dateRangeId,
          response: 'preferably_not',
          comment: 'I can make it work',
        },
      })

      // Get event and verify votes are included in pool
      const response = await request.get(`${API_BASE}/api/events/${eventId}`, {
        headers: authHeaders(token),
      })
      const body = await response.json()

      // Find the date range and verify it has the vote ID
      const dateRanges = getObjectsByType(body.objects, 'dateRange')
      const dateRange = dateRanges.find(
        (dr: PoolObject) => dr.id === dateRangeId
      )
      expect((dateRange as { voteIds: string[] })?.voteIds).toHaveLength(1)

      // Find the vote and verify its data
      const votes = getObjectsByType(body.objects, 'vote')
      expect(votes).toHaveLength(1)
      expect(votes[0]?.response).toBe('preferably_not')
    })

    test('non-workspace-member cannot view event', async ({ request }) => {
      const { token: ownerToken } = await getTestSession(
        request,
        TEST_EMAIL,
        TEST_NAME
      )
      const { token: otherToken } = await getTestSession(
        request,
        TEST_EMAIL_2,
        TEST_NAME_2
      )
      const { eventId } = await createTestEvent(request, ownerToken)

      // Other user (not in workspace) cannot view the event
      const response = await request.get(`${API_BASE}/api/events/${eventId}`, {
        headers: authHeaders(otherToken),
      })

      expect(response.status()).toBe(403)
      const body = await response.json()
      expect(body.error).toBe('Access denied')
    })

    test('non-workspace-member cannot vote on event', async ({ request }) => {
      const { token: ownerToken } = await getTestSession(
        request,
        TEST_EMAIL,
        TEST_NAME
      )
      const { token: otherToken } = await getTestSession(
        request,
        TEST_EMAIL_2,
        TEST_NAME_2
      )
      const { eventId, dateRangeId } = await createTestEvent(
        request,
        ownerToken
      )

      // Other user (not in workspace) cannot vote on the event
      const response = await request.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          headers: authHeaders(otherToken),
          data: {
            date_range_id: dateRangeId,
            response: 'yes',
          },
        }
      )

      expect(response.status()).toBe(403)
      const body = await response.json()
      expect(body.error).toBe('Access denied')
    })
  })

  test.describe('Date Poll API', () => {
    test('POST /api/events/:id/poll creates a date poll', async ({
      request,
    }) => {
      const { token } = await getTestSession(request)

      // Create event without poll
      const eventResponse = await request.post(`${API_BASE}/api/events`, {
        headers: authHeaders(token),
        data: { name: 'Poll Test Event' },
      })
      const eventBody = await eventResponse.json()
      const event = getObjectByType(eventBody.objects, 'event')

      // Create poll
      const deadline = new Date(
        Date.now() + 7 * 24 * 60 * 60 * 1000
      ).toISOString()
      const pollResponse = await request.post(
        `${API_BASE}/api/events/${event!.id}/poll`,
        {
          headers: authHeaders(token),
          data: { deadline },
        }
      )

      expect(pollResponse.status()).toBe(201)
      const pollBody = await pollResponse.json()
      const poll = getObjectByType(pollBody.objects, 'datePoll')
      expect(poll).toHaveProperty('id')
      expect(poll?.status).toBe('open')
    })

    test('POST /api/events/:id/poll/close selects a winner', async ({
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      const closeResponse = await request.post(
        `${API_BASE}/api/events/${eventId}/poll/close`,
        {
          headers: authHeaders(token),
          data: { selected_date_range_id: dateRangeId },
        }
      )

      expect(closeResponse.ok()).toBeTruthy()
      const closeBody = await closeResponse.json()
      const poll = getObjectByType(closeBody.objects, 'datePoll')
      expect(poll?.status).toBe('resolved')
      expect(poll?.selectedDateRangeId).toBe(dateRangeId)
    })

    test('POST /api/events/:id/poll/reopen reopens a resolved poll', async ({
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      // Close the poll
      await request.post(`${API_BASE}/api/events/${eventId}/poll/close`, {
        headers: authHeaders(token),
        data: { selected_date_range_id: dateRangeId },
      })

      // Reopen
      const newDeadline = new Date(
        Date.now() + 14 * 24 * 60 * 60 * 1000
      ).toISOString()
      const reopenResponse = await request.post(
        `${API_BASE}/api/events/${eventId}/poll/reopen`,
        {
          headers: authHeaders(token),
          data: { deadline: newDeadline },
        }
      )

      expect(reopenResponse.ok()).toBeTruthy()
      const reopenBody = await reopenResponse.json()
      const poll = getObjectByType(reopenBody.objects, 'datePoll')
      expect(poll?.status).toBe('open')
      expect(poll?.selectedDateRangeId).toBeNull()
    })

    test('voting fails on a closed poll', async ({ request }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      // Close the poll
      await request.post(`${API_BASE}/api/events/${eventId}/poll/close`, {
        headers: authHeaders(token),
        data: { selected_date_range_id: dateRangeId },
      })

      // Try to vote
      const voteResponse = await request.post(
        `${API_BASE}/api/events/${eventId}/votes`,
        {
          headers: authHeaders(token),
          data: {
            date_range_id: dateRangeId,
            response: 'yes',
          },
        }
      )

      expect(voteResponse.status()).toBe(400)
      const body = await voteResponse.json()
      expect(body.error).toBe('Poll is not open for voting')
    })
  })

  test.describe('Votes UI', () => {
    test('event page redirects to login when not authenticated', async ({
      page,
    }) => {
      await page.goto('/events/some-id')
      await expect(page).toHaveURL('/login')
    })

    test('can navigate to event page from events list', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto('/events')
      await page.getByText('Voting Test Event').first().click()

      // Verify we're on an event detail page (URL contains /events/ followed by a UUID)
      await expect(page).toHaveURL(/\/events\/[0-9a-f-]+$/)
      await expect(page.getByTestId('event-name')).toContainText(
        'Voting Test Event'
      )
    })

    test('vote page shows date ranges with voting buttons', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}/vote`)

      // Should see vote buttons
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).toBeVisible()
      await expect(
        page
          .getByRole('button', { name: 'Preferably not', exact: true })
          .first()
      ).toBeVisible()
      await expect(
        page.getByRole('button', { name: 'No', exact: true }).first()
      ).toBeVisible()
    })

    test('can vote on a date range', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}/vote`)

      // Click Yes button on first date range
      await page
        .getByRole('button', { name: 'Yes', exact: true })
        .first()
        .click()

      // Button should now be highlighted (has green background)
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).toHaveClass(/bg-green-600/)

      // Vote summary should show 1 yes
      await expect(
        page.getByText('1 yes, 0 preferably not, 0 no').first()
      ).toBeVisible()
    })

    test('can change vote', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}/vote`)

      // Vote Yes first
      await page
        .getByRole('button', { name: 'Yes', exact: true })
        .first()
        .click()
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).toHaveClass(/bg-green-600/)

      // Change to No
      await page
        .getByRole('button', { name: 'No', exact: true })
        .first()
        .click()
      await expect(
        page.getByRole('button', { name: 'No', exact: true }).first()
      ).toHaveClass(/bg-red-600/)
      await expect(
        page.getByRole('button', { name: 'Yes', exact: true }).first()
      ).not.toHaveClass(/bg-green-600/)

      // Vote summary should now show 1 no
      await expect(
        page.getByText('0 yes, 0 preferably not, 1 no').first()
      ).toBeVisible()
    })

    test('can expand voters list', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}/vote`)

      // Vote first
      await page
        .getByRole('button', { name: 'Yes', exact: true })
        .first()
        .click()

      // Expand voters list
      await page
        .getByRole('button', { name: /Show votes/ })
        .first()
        .click()

      // Should see the voter
      await expect(page.getByText(TEST_NAME).first()).toBeVisible()
    })

    test('back button returns to events list', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)
      await page.getByRole('button', { name: 'Back to Events' }).click()

      await expect(page).toHaveURL('/events')
    })

    test('event page shows new user in awaiting votes section', async ({
      page,
      request,
    }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      // Navigate to the event page first
      await page.goto(`/events/${eventId}`)

      // Wait for the event name to be visible (indicates page is loaded)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: 10000,
      })

      // The awaiting votes section should show initially (just the creator)
      const awaitingSection = page.locator('section', {
        has: page.getByRole('heading', { name: 'Awaiting Votes' }),
      })
      await expect(
        page.getByRole('heading', { name: 'Awaiting Votes' })
      ).toBeVisible({ timeout: 10000 })

      // Now add a new user via API (simulating another tab/user adding someone)
      const newUserName = `New User ${Date.now()}`
      const newUserEmail = `new-user-${Date.now()}@example.com`
      await request.post('http://localhost:9293/api/users', {
        headers: { Authorization: `Bearer ${token}` },
        data: { name: newUserName, email: newUserEmail },
      })

      // The new user should appear in real-time via WebSocket (no page refresh)
      await expect(awaitingSection.getByText(newUserName)).toBeVisible({
        timeout: 10000,
      })

      // Should show count of people who haven't voted
      await expect(
        awaitingSection.getByText(/haven't fully voted yet/)
      ).toBeVisible()
    })
  })
})
