import { test, expect, Page, APIRequestContext } from '@playwright/test'

const API_BASE = 'http://localhost:9293'
const TEST_EMAIL = 'e2e-events@example.com'
const TEST_NAME = 'E2E Events User'

// Helper to get an authenticated session for testing
async function getTestSession(request: APIRequestContext): Promise<{ token: string; userId: string }> {
  const response = await request.post(`${API_BASE}/api/test/session`, {
    data: { email: TEST_EMAIL, name: TEST_NAME }
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

test.describe('Events Feature', () => {
  test.describe('Events API - Unauthenticated', () => {
    test('GET /api/events returns 401 without auth', async ({ request }) => {
      const response = await request.get(`${API_BASE}/api/events`)
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })

    test('POST /api/events returns 401 without auth', async ({ request }) => {
      const response = await request.post(`${API_BASE}/api/events`, {
        data: { name: 'Test Event' }
      })
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })

    test('GET /api/events/:id returns 401 without auth', async ({ request }) => {
      const response = await request.get(`${API_BASE}/api/events/some-id`)
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })

    test('PUT /api/events/:id returns 401 without auth', async ({ request }) => {
      const response = await request.put(`${API_BASE}/api/events/some-id`, {
        data: { name: 'Updated Event' }
      })
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })

    test('DELETE /api/events/:id returns 401 without auth', async ({ request }) => {
      const response = await request.delete(`${API_BASE}/api/events/some-id`)
      expect(response.status()).toBe(401)
      const body = await response.json()
      expect(body.error).toBe('Authorization required')
    })
  })

  test.describe('Events API - Authenticated', () => {
    test('GET /api/events returns list of events', async ({ request }) => {
      const { token } = await getTestSession(request)
      const response = await request.get(`${API_BASE}/api/events`, {
        headers: authHeaders(token)
      })
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body).toHaveProperty('events')
      expect(Array.isArray(body.events)).toBeTruthy()
    })

    test('POST /api/events creates a new event', async ({ request }) => {
      const { token } = await getTestSession(request)
      const response = await request.post(`${API_BASE}/api/events`, {
        headers: authHeaders(token),
        data: {
          name: 'Test Event',
          description: 'A test event description',
          date_ranges: [
            { start_date: '2025-03-01', end_date: '2025-03-07' }
          ]
        }
      })
      expect(response.status()).toBe(201)
      const body = await response.json()
      expect(body.event).toHaveProperty('id')
      expect(body.event.name).toBe('Test Event')
      expect(body.event.description).toBe('A test event description')
      expect(body.event.date_ranges).toHaveLength(1)
      expect(body.event.date_ranges[0].start_date).toBe('2025-03-01')
      expect(body.event.date_ranges[0].end_date).toBe('2025-03-07')
    })

    test('POST /api/events requires name', async ({ request }) => {
      const { token } = await getTestSession(request)
      const response = await request.post(`${API_BASE}/api/events`, {
        headers: authHeaders(token),
        data: { description: 'No name provided' }
      })
      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('Name is required')
    })

    test('full CRUD lifecycle for events', async ({ request }) => {
      const { token } = await getTestSession(request)

      // Create
      const createResponse = await request.post(`${API_BASE}/api/events`, {
        headers: authHeaders(token),
        data: {
          name: 'CRUD Test Event',
          date_ranges: [
            { start_date: '2025-04-01', end_date: '2025-04-05' }
          ]
        }
      })
      expect(createResponse.status()).toBe(201)
      const { event: createdEvent } = await createResponse.json()
      const eventId = createdEvent.id

      // Read
      const getResponse = await request.get(`${API_BASE}/api/events/${eventId}`, {
        headers: authHeaders(token)
      })
      expect(getResponse.ok()).toBeTruthy()
      const { event: fetchedEvent } = await getResponse.json()
      expect(fetchedEvent.name).toBe('CRUD Test Event')

      // Update
      const updateResponse = await request.put(`${API_BASE}/api/events/${eventId}`, {
        headers: authHeaders(token),
        data: {
          name: 'Updated CRUD Event',
          description: 'Now with a description',
          date_ranges: [
            { start_date: '2025-04-01', end_date: '2025-04-05' },
            { start_date: '2025-04-10', end_date: '2025-04-12' }
          ]
        }
      })
      expect(updateResponse.ok()).toBeTruthy()
      const { event: updatedEvent } = await updateResponse.json()
      expect(updatedEvent.name).toBe('Updated CRUD Event')
      expect(updatedEvent.description).toBe('Now with a description')
      expect(updatedEvent.date_ranges).toHaveLength(2)

      // Delete
      const deleteResponse = await request.delete(`${API_BASE}/api/events/${eventId}`, {
        headers: authHeaders(token)
      })
      expect(deleteResponse.ok()).toBeTruthy()
      const deleteBody = await deleteResponse.json()
      expect(deleteBody.message).toBe('Event deleted successfully')

      // Verify deleted
      const verifyResponse = await request.get(`${API_BASE}/api/events/${eventId}`, {
        headers: authHeaders(token)
      })
      expect(verifyResponse.status()).toBe(404)
    })

    test('GET /api/events/:id returns 404 for non-existent event', async ({ request }) => {
      const { token } = await getTestSession(request)
      const response = await request.get(`${API_BASE}/api/events/00000000-0000-0000-0000-000000000000`, {
        headers: authHeaders(token)
      })
      expect(response.status()).toBe(404)
      const body = await response.json()
      expect(body.error).toBe('Event not found')
    })
  })

  test.describe('Events UI - Unauthenticated Navigation', () => {
    test('events page redirects to login when not authenticated', async ({ page }) => {
      await page.goto('/events')
      await expect(page).toHaveURL('/login')
    })

    test('events/new page redirects to login when not authenticated', async ({ page }) => {
      await page.goto('/events/new')
      await expect(page).toHaveURL('/login')
    })

    test('events edit page redirects to login when not authenticated', async ({ page }) => {
      await page.goto('/events/some-id/edit')
      await expect(page).toHaveURL('/login')
    })
  })

  test.describe('Events UI - Authenticated', () => {
    test('events page displays header and new event button', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      await setupAuthenticatedPage(page, token)
      await page.goto('/events')

      await expect(page.getByTestId('page-title')).toContainText('Events')
      await expect(page.getByTestId('new-event-button')).toBeVisible()
    })

    test('navigation includes Events link', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      await setupAuthenticatedPage(page, token)
      await page.goto('/')

      await expect(page.getByRole('link', { name: 'Events' })).toBeVisible()
    })

    test('can navigate to create event page', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      await setupAuthenticatedPage(page, token)
      await page.goto('/events')

      await page.getByTestId('new-event-button').click()
      await expect(page).toHaveURL('/events/new')
      await expect(page.locator('h1')).toContainText('Create Event')
    })

    test('create event form has required fields', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      await setupAuthenticatedPage(page, token)
      await page.goto('/events/new')

      await expect(page.getByTestId('event-name-input')).toBeVisible()
      await expect(page.getByTestId('event-description-input')).toBeVisible()
      await expect(page.getByText('Date Ranges', { exact: true })).toBeVisible()
      await expect(page.getByTestId('add-date-range-button')).toBeVisible()
    })

    test('can create an event through UI', async ({ page, request }) => {
      const { token } = await getTestSession(request)
      await setupAuthenticatedPage(page, token)
      await page.goto('/events/new')

      // Fill in the form
      await page.getByTestId('event-name-input').fill('UI Test Event')
      await page.getByTestId('event-description-input').fill('Created via UI test')

      // Add a date range
      await page.getByTestId('add-date-range-button').click()

      // Wait for modal to appear with transition
      await expect(page.getByText('Select Date Range')).toBeVisible({ timeout: 10000 })

      // Click on two dates to select a range using specific date test IDs
      // Use dates from next month to ensure they're always in the future
      const today = new Date()
      const nextMonth = new Date(today.getFullYear(), today.getMonth() + 1, 1)
      const startDate = `${nextMonth.getFullYear()}-${String(nextMonth.getMonth() + 1).padStart(2, '0')}-10`
      const endDate = `${nextMonth.getFullYear()}-${String(nextMonth.getMonth() + 1).padStart(2, '0')}-15`

      await page.getByTestId(`calendar-day-${startDate}`).click()
      await page.getByTestId(`calendar-day-${endDate}`).click()

      // Save the range
      await page.getByTestId('modal-save-button').click()

      // Verify the range was added (modal should close)
      await expect(page.getByText('Select Date Range')).not.toBeVisible({ timeout: 5000 })

      // Submit the form
      await page.getByTestId('submit-button').click()

      // Should redirect to events list
      await expect(page).toHaveURL('/events', { timeout: 10000 })

      // Event should appear in the list (use first() since previous runs may have created duplicates)
      await expect(page.getByTestId('events-list').getByTestId('event-name').filter({ hasText: 'UI Test Event' }).first()).toBeVisible()
    })
  })
})

// Integration tests that verify the API contract
test.describe('Events API Contract', () => {
  test('API returns proper JSON content type', async ({ request }) => {
    const response = await request.get(`${API_BASE}/api/events`)
    expect(response.headers()['content-type']).toContain('application/json')
  })

  test('API returns proper error structure', async ({ request }) => {
    const response = await request.get(`${API_BASE}/api/events`)
    const body = await response.json()
    expect(body).toHaveProperty('error')
    expect(typeof body.error).toBe('string')
  })
})
