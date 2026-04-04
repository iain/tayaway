import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getObjectByType,
  getTestSession,
  setupAuthenticatedPage,
  PAGE_LOAD_TIMEOUT,
  newApiContext,
} from '../helpers'

const TEST_EMAIL = 'e2e-events@example.com'
const TEST_NAME = 'E2E Events User'

test.describe('Events Feature', () => {
  test.describe('Events API - Unauthenticated', () => {
    test('all event endpoints require auth', async ({ request }) => {
      const responses = await Promise.all([
        request.get(`${API_BASE}/api/events`),
        request.post(`${API_BASE}/api/events`, {
          data: { name: 'Test Event' },
        }),
        request.get(`${API_BASE}/api/events/some-id`),
        request.put(`${API_BASE}/api/events/some-id`, {
          data: { name: 'Updated Event' },
        }),
        request.delete(`${API_BASE}/api/events/some-id`),
      ])
      for (const response of responses) {
        expect(response.status()).toBe(401)
        const body = await response.json()
        expect(body.error).toBe('Authorization required')
      }
    })
  })

  test.describe('Events API - Authenticated', () => {
    let apiContext: APIRequestContext

    test.beforeAll(async ({ playwright }) => {
      apiContext = await newApiContext(playwright)
      await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('GET /api/events returns list of events', async () => {
      const response = await apiContext.get(`${API_BASE}/api/events`)
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body).toHaveProperty('objects')
      expect(Array.isArray(body.objects)).toBeTruthy()
    })

    test('POST /api/events creates a new event', async () => {
      const response = await apiContext.post(`${API_BASE}/api/events`, {
        data: {
          name: 'Test Event',
          description: 'A test event description',
        },
      })
      expect(response.status()).toBe(201)
      const body = await response.json()
      const event = getObjectByType(body.objects, 'event')
      expect(event).toHaveProperty('id')
      expect(event?.name).toBe('Test Event')
      expect(event?.description).toBe('A test event description')
      expect(event?.datePollId).toBeNull()
    })

    test('POST /api/events requires name', async () => {
      const response = await apiContext.post(`${API_BASE}/api/events`, {
        data: { description: 'No name provided' },
      })
      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBe('Name is required')
    })

    test('full CRUD lifecycle for events', async () => {
      // Create
      const createResponse = await apiContext.post(`${API_BASE}/api/events`, {
        data: {
          name: 'CRUD Test Event',
        },
      })
      expect(createResponse.status()).toBe(201)
      const createBody = await createResponse.json()
      const createdEvent = getObjectByType(createBody.objects, 'event')
      const eventId = createdEvent!.id

      // Read
      const getResponse = await apiContext.get(
        `${API_BASE}/api/events/${eventId}`
      )
      expect(getResponse.ok()).toBeTruthy()
      const getBody = await getResponse.json()
      const fetchedEvent = getObjectByType(getBody.objects, 'event')
      expect(fetchedEvent?.name).toBe('CRUD Test Event')

      // Update
      const updateResponse = await apiContext.put(
        `${API_BASE}/api/events/${eventId}`,
        {
          data: {
            name: 'Updated CRUD Event',
            description: 'Now with a description',
          },
        }
      )
      expect(updateResponse.ok()).toBeTruthy()
      const updateBody = await updateResponse.json()
      const updatedEvent = getObjectByType(updateBody.objects, 'event')
      expect(updatedEvent?.name).toBe('Updated CRUD Event')
      expect(updatedEvent?.description).toBe('Now with a description')

      // Delete
      const deleteResponse = await apiContext.delete(
        `${API_BASE}/api/events/${eventId}`
      )
      expect(deleteResponse.ok()).toBeTruthy()
      const deleteBody = await deleteResponse.json()
      expect(deleteBody.deleted).toHaveLength(1)
      expect(deleteBody.deleted[0].objectType).toBe('event')
      expect(deleteBody.deleted[0].id).toBe(eventId)

      // Verify deleted
      const verifyResponse = await apiContext.get(
        `${API_BASE}/api/events/${eventId}`
      )
      expect(verifyResponse.status()).toBe(410)
    })

    test('GET /api/events/:id returns 404 for non-existent event', async () => {
      const response = await apiContext.get(
        `${API_BASE}/api/events/00000000-0000-0000-0000-000000000000`
      )
      expect(response.status()).toBe(404)
      const body = await response.json()
      expect(body.error).toBe('Event not found')
    })
  })

  test.describe('Events UI - Unauthenticated Navigation', () => {
    test('events page redirects to login when not authenticated', async ({
      page,
    }) => {
      await page.goto('/events')
      await expect(page).toHaveURL('/login')
    })

    test('events/new page redirects to login when not authenticated', async ({
      page,
    }) => {
      await page.goto('/events/new')
      await expect(page).toHaveURL('/login')
    })
  })

  test.describe('Events UI - Authenticated', () => {
    let sessionToken: string

    test.beforeAll(async ({ playwright }) => {
      const ctx = await newApiContext(playwright)
      const { token } = await getTestSession(ctx, TEST_EMAIL, TEST_NAME)
      sessionToken = token
      await ctx.dispose()
    })

    test('events page UI: header, navigation, modal fields, and event creation', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)

      // Navigation includes Events link
      await page.goto('/')
      await expect(page.getByRole('link', { name: 'Events' })).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Events page displays header and new event button
      await page.goto('/events')
      await expect(page.getByTestId('page-title')).toContainText('Events', {
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(page.getByTestId('new-event-button')).toBeVisible()

      // New event button opens wizard
      await page.getByTestId('new-event-button').click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(
        page.getByRole('dialog').getByRole('heading', { name: 'New Event' })
      ).toBeVisible()
      await expect(page.getByLabel('Name')).toBeVisible()
      await expect(page.getByLabel(/Description/)).toBeVisible()

      // Fill in the form, advance through wizard, and create event
      await page.getByLabel('Name').fill('Modal Test Event')
      await page.getByLabel(/Description/).fill('Created via wizard test')
      await page.getByRole('button', { name: 'Next' }).click()
      await page.getByRole('button', { name: /Skip/ }).click()

      // Should navigate to the event page
      await expect(page).toHaveURL(/\/events\/[\w-]+$/, {
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Event name should be visible on the event page
      await expect(page.getByTestId('event-name')).toContainText(
        'Modal Test Event'
      )
    })
  })
})

test.describe('Events categorization - Happening Now', () => {
  let sessionToken: string
  let apiContext: APIRequestContext

  test.beforeAll(async ({ playwright }) => {
    apiContext = await newApiContext(playwright)
    const { token } = await getTestSession(
      apiContext,
      'e2e-events-categorization@example.com',
      'E2E Categorization User'
    )
    sessionToken = token
  })

  test.afterAll(async () => {
    await apiContext.dispose()
  })

  function todayStr(): string {
    return new Date().toISOString().slice(0, 10)
  }

  function offsetDate(days: number): string {
    const d = new Date()
    d.setDate(d.getDate() + days)
    return d.toISOString().slice(0, 10)
  }

  test('events page shows "Happening Now" section for current events', async ({
    page,
  }) => {
    // Create a current event (started yesterday, ends tomorrow)
    await apiContext.post(`${API_BASE}/api/events`, {
      data: {
        name: 'Current Trip',
        start_date: offsetDate(-1),
        end_date: offsetDate(1),
      },
    })

    // Create an upcoming event (starts next week)
    await apiContext.post(`${API_BASE}/api/events`, {
      data: {
        name: 'Future Trip',
        start_date: offsetDate(7),
        end_date: offsetDate(10),
      },
    })

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/events')

    await expect(page.getByTestId('events-list')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // "Happening Now" section should be visible with the current event
    const happeningNow = page.getByRole('heading', { name: 'Happening Now' })
    await expect(happeningNow).toBeVisible()

    // The current event should be in the list
    await expect(page.getByText('Current Trip')).toBeVisible()

    // "Upcoming" section should also be visible
    await expect(page.getByRole('heading', { name: 'Upcoming' })).toBeVisible()
    await expect(page.getByText('Future Trip')).toBeVisible()
  })

  test('dashboard shows "Happening now" section for current events', async ({
    page,
  }) => {
    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/')

    // Dashboard should show "Happening now" heading
    const happeningNowHeading = page.getByRole('heading', {
      name: 'Happening now',
    })
    await expect(happeningNowHeading).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // The current event should be listed within the happening now section
    const happeningNowSection = page.getByTestId('happening-now-section')
    await expect(happeningNowSection.getByText('Current Trip')).toBeVisible()
  })

  test('event starting today appears in "Happening Now", not "Upcoming"', async ({
    page,
  }) => {
    await apiContext.post(`${API_BASE}/api/events`, {
      data: {
        name: 'Starting Today Trip',
        start_date: todayStr(),
        end_date: offsetDate(3),
      },
    })

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/events')

    await expect(page.getByTestId('events-list')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // The "Happening Now" section should contain the event starting today
    const happeningNowSection = page.getByTestId('happening-now-section')
    await expect(
      happeningNowSection.getByText('Starting Today Trip')
    ).toBeVisible()

    // It should NOT appear in the "Upcoming" section
    const upcomingSection = page.getByTestId('upcoming-section')
    await expect(
      upcomingSection.getByText('Starting Today Trip')
    ).not.toBeVisible()
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
