import { test, expect, Page, APIRequestContext } from '@playwright/test'

const API_BASE = 'http://localhost:9293'
const TEST_EMAIL = 'e2e-voting@example.com'
const TEST_EMAIL_2 = 'e2e-voting-2@example.com'
const TEST_NAME = 'E2E Voting User'
const TEST_NAME_2 = 'E2E Voting User 2'

// Helper to get an authenticated session for testing
async function getTestSession(request: APIRequestContext, email = TEST_EMAIL, name = TEST_NAME): Promise<{ token: string; userId: string }> {
  const response = await request.post(`${API_BASE}/api/test/session`, {
    data: { email, name }
  })
  if (!response.ok()) {
    throw new Error(`Failed to create test session: ${response.status()}`)
  }
  const body = await response.json()
  return { token: body.session_token, userId: body.user.id }
}

// Helper to make authenticated API requests
function authHeaders(token: string): { Authorization: string } {
  return { Authorization: `Bearer ${token}` }
}

// Helper to set up authenticated page
async function setupAuthenticatedPage(page: Page, token: string): Promise<void> {
  await page.goto('/')
  await page.evaluate((t) => {
    localStorage.setItem('session_token', t)
  }, token)
}

// Helper to create an event with date ranges
async function createTestEvent(request: APIRequestContext, token: string): Promise<{ eventId: string; dateRangeId: string }> {
  const response = await request.post(`${API_BASE}/api/events`, {
    headers: authHeaders(token),
    data: {
      name: 'Voting Test Event',
      description: 'An event for testing voting',
      date_ranges: [
        { start_date: '2025-06-01', end_date: '2025-06-07' },
        { start_date: '2025-06-15', end_date: '2025-06-20' }
      ]
    }
  })
  const body = await response.json()
  return {
    eventId: body.event.id,
    dateRangeId: body.event.date_ranges[0].id
  }
}

test.describe('Voting Feature', () => {
  test.describe('Votes API - Unauthenticated', () => {
    test('GET /api/events/:id/votes returns 401 without auth', async ({ request }) => {
      const response = await request.get(`${API_BASE}/api/events/some-id/votes`)
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })

    test('POST /api/events/:id/votes returns 401 without auth', async ({ request }) => {
      const response = await request.post(`${API_BASE}/api/events/some-id/votes`, {
        data: { date_range_id: 'some-id', response: 'yes' }
      })
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })

    test('DELETE /api/events/:id/votes/:vote_id returns 401 without auth', async ({ request }) => {
      const response = await request.delete(`${API_BASE}/api/events/some-id/votes/some-vote-id`)
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })
  })

  test.describe('Votes API - Authenticated', () => {
    test('POST /api/events/:id/votes creates a vote', async ({ request }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      const response = await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token),
        data: {
          date_range_id: dateRangeId,
          response: 'yes',
          comment: 'This date works great!'
        }
      })

      expect(response.status()).toBe(201)
      const body = await response.json()
      expect(body.vote).toHaveProperty('id')
      expect(body.vote.response).toBe('yes')
      expect(body.vote.comment).toBe('This date works great!')
      expect(body.vote.date_range_id).toBe(dateRangeId)
    })

    test('POST /api/events/:id/votes updates existing vote', async ({ request }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      // Create initial vote
      await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token),
        data: {
          date_range_id: dateRangeId,
          response: 'yes'
        }
      })

      // Update to different response
      const response = await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token),
        data: {
          date_range_id: dateRangeId,
          response: 'no',
          comment: 'Changed my mind'
        }
      })

      expect(response.status()).toBe(200)
      const body = await response.json()
      expect(body.vote.response).toBe('no')
      expect(body.vote.comment).toBe('Changed my mind')
    })

    test('POST /api/events/:id/votes validates response value', async ({ request }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      const response = await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token),
        data: {
          date_range_id: dateRangeId,
          response: 'invalid_response'
        }
      })

      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('Invalid response value')
    })

    test('POST /api/events/:id/votes requires date_range_id', async ({ request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)

      const response = await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token),
        data: { response: 'yes' }
      })

      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('date_range_id is required')
    })

    test('POST /api/events/:id/votes requires response', async ({ request }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      const response = await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token),
        data: { date_range_id: dateRangeId }
      })

      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('response is required')
    })

    test('POST /api/events/:id/votes rejects date_range from different event', async ({ request }) => {
      const { token } = await getTestSession(request)
      const { dateRangeId } = await createTestEvent(request, token)
      const { eventId: otherEventId } = await createTestEvent(request, token)

      const response = await request.post(`${API_BASE}/api/events/${otherEventId}/votes`, {
        headers: authHeaders(token),
        data: {
          date_range_id: dateRangeId,
          response: 'yes'
        }
      })

      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('Date range does not belong to this event')
    })

    test('GET /api/events/:id/votes returns all votes for event', async ({ request }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      // Create a vote
      await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token),
        data: {
          date_range_id: dateRangeId,
          response: 'yes'
        }
      })

      const response = await request.get(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token)
      })

      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body.votes).toHaveLength(1)
      expect(body.votes[0].response).toBe('yes')
    })

    test('DELETE /api/events/:id/votes/:vote_id removes vote', async ({ request }) => {
      const { token } = await getTestSession(request)
      const { eventId, dateRangeId } = await createTestEvent(request, token)

      // Create a vote
      const createResponse = await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token),
        data: {
          date_range_id: dateRangeId,
          response: 'yes'
        }
      })
      const { vote } = await createResponse.json()

      // Delete the vote
      const deleteResponse = await request.delete(`${API_BASE}/api/events/${eventId}/votes/${vote.id}`, {
        headers: authHeaders(token)
      })

      expect(deleteResponse.ok()).toBeTruthy()
      const body = await deleteResponse.json()
      expect(body.message).toBe('Vote deleted successfully')

      // Verify vote is gone
      const getResponse = await request.get(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token)
      })
      const { votes } = await getResponse.json()
      expect(votes).toHaveLength(0)
    })

    test('DELETE /api/events/:id/votes/:vote_id returns 403 for other user vote', async ({ request }) => {
      const { token: token1 } = await getTestSession(request, TEST_EMAIL, TEST_NAME)
      const { token: token2 } = await getTestSession(request, TEST_EMAIL_2, TEST_NAME_2)
      const { eventId, dateRangeId } = await createTestEvent(request, token1)

      // User 1 creates a vote
      const createResponse = await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(token1),
        data: {
          date_range_id: dateRangeId,
          response: 'yes'
        }
      })
      const { vote } = await createResponse.json()

      // User 2 tries to delete User 1's vote
      const deleteResponse = await request.delete(`${API_BASE}/api/events/${eventId}/votes/${vote.id}`, {
        headers: authHeaders(token2)
      })

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
          comment: 'I can make it work'
        }
      })

      // Get event and verify votes are included
      const response = await request.get(`${API_BASE}/api/events/${eventId}`, {
        headers: authHeaders(token)
      })
      const { event } = await response.json()

      expect(event.date_ranges[0].votes).toHaveLength(1)
      expect(event.date_ranges[0].votes[0].response).toBe('preferably_not')
      expect(event.date_ranges[0].vote_summary).toEqual({
        yes: 0,
        no: 0,
        preferably_not: 1,
        total: 1
      })
    })

    test('any authenticated user can view any event', async ({ request }) => {
      const { token: ownerToken } = await getTestSession(request, TEST_EMAIL, TEST_NAME)
      const { token: otherToken } = await getTestSession(request, TEST_EMAIL_2, TEST_NAME_2)
      const { eventId } = await createTestEvent(request, ownerToken)

      // Other user can view the event
      const response = await request.get(`${API_BASE}/api/events/${eventId}`, {
        headers: authHeaders(otherToken)
      })

      expect(response.ok()).toBeTruthy()
      const { event } = await response.json()
      expect(event.name).toBe('Voting Test Event')
    })

    test('any authenticated user can vote on any event', async ({ request }) => {
      const { token: ownerToken } = await getTestSession(request, TEST_EMAIL, TEST_NAME)
      const { token: otherToken } = await getTestSession(request, TEST_EMAIL_2, TEST_NAME_2)
      const { eventId, dateRangeId } = await createTestEvent(request, ownerToken)

      // Other user can vote on the event
      const response = await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
        headers: authHeaders(otherToken),
        data: {
          date_range_id: dateRangeId,
          response: 'yes'
        }
      })

      expect(response.status()).toBe(201)
    })
  })

  test.describe('Votes UI', () => {
    test('event page redirects to login when not authenticated', async ({ page }) => {
      await page.goto('/events/some-id')
      await expect(page).toHaveURL('/login')
    })

    test('can navigate to event page from events list', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto('/events')
      await page.getByText('Voting Test Event').first().click()

      // Verify we're on an event detail page (URL contains /events/ followed by a UUID)
      await expect(page).toHaveURL(/\/events\/[0-9a-f-]+$/)
      await expect(page.getByTestId('event-name')).toContainText('Voting Test Event')
    })

    test('event page shows date ranges with voting buttons', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)

      // Should see vote buttons
      await expect(page.getByRole('button', { name: 'Yes', exact: true }).first()).toBeVisible()
      await expect(page.getByRole('button', { name: 'Preferably not', exact: true }).first()).toBeVisible()
      await expect(page.getByRole('button', { name: 'No', exact: true }).first()).toBeVisible()
    })

    test('can vote on a date range', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)

      // Click Yes button on first date range
      await page.getByRole('button', { name: 'Yes', exact: true }).first().click()

      // Button should now be highlighted (has green background)
      await expect(page.getByRole('button', { name: 'Yes', exact: true }).first()).toHaveClass(/bg-green-600/)

      // Vote summary should show 1 yes
      await expect(page.getByText('1 yes, 0 preferably not, 0 no').first()).toBeVisible()
    })

    test('can change vote', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)

      // Vote Yes first
      await page.getByRole('button', { name: 'Yes', exact: true }).first().click()
      await expect(page.getByRole('button', { name: 'Yes', exact: true }).first()).toHaveClass(/bg-green-600/)

      // Change to No
      await page.getByRole('button', { name: 'No', exact: true }).first().click()
      await expect(page.getByRole('button', { name: 'No', exact: true }).first()).toHaveClass(/bg-red-600/)
      await expect(page.getByRole('button', { name: 'Yes', exact: true }).first()).not.toHaveClass(/bg-green-600/)

      // Vote summary should now show 1 no
      await expect(page.getByText('0 yes, 0 preferably not, 1 no').first()).toBeVisible()
    })

    test('can expand voters list', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      const { eventId } = await createTestEvent(request, token)
      await setupAuthenticatedPage(page, token)

      await page.goto(`/events/${eventId}`)

      // Vote first
      await page.getByRole('button', { name: 'Yes', exact: true }).first().click()

      // Expand voters list
      await page.getByRole('button', { name: /Show votes/ }).first().click()

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
  })
})
