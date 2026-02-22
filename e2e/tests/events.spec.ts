import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getObjectByType,
  getTestSession,
  setupAuthenticatedPage,
  PAGE_LOAD_TIMEOUT,
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
      apiContext = await playwright.request.newContext()
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

    test('events edit page redirects to login when not authenticated', async ({
      page,
    }) => {
      await page.goto('/events/some-id/edit')
      await expect(page).toHaveURL('/login')
    })
  })

  test.describe('Events UI - Authenticated', () => {
    let sessionToken: string

    test.beforeAll(async ({ playwright }) => {
      const ctx = await playwright.request.newContext()
      const { token } = await getTestSession(ctx, TEST_EMAIL, TEST_NAME)
      sessionToken = token
      await ctx.dispose()
    })

    test('events page displays header and new event button', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/events')

      await expect(page.getByTestId('page-title')).toContainText('Events')
      await expect(page.getByTestId('new-event-button')).toBeVisible()
    })

    test('navigation includes Events link', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/')

      await expect(page.getByRole('link', { name: 'Events' })).toBeVisible()
    })

    test('new event button opens modal with required fields', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/events')

      await page.getByTestId('new-event-button').click()
      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(
        page.getByRole('dialog').getByRole('heading', { name: 'New Event' })
      ).toBeVisible()
      await expect(page.getByLabel('Name')).toBeVisible()
      await expect(page.getByLabel(/Description/)).toBeVisible()
      await expect(page.getByTestId('modal-save-button')).toBeVisible()
    })

    test('can create an event through modal', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/events')

      // Open the create event modal
      await page.getByTestId('new-event-button').click()
      await expect(page.getByRole('dialog')).toBeVisible()

      // Fill in the form
      await page.getByLabel('Name').fill('Modal Test Event')
      await page.getByLabel(/Description/).fill('Created via modal test')

      // Submit the form
      await page.getByTestId('modal-save-button').click()

      // Should redirect to the event planning page
      await expect(page).toHaveURL(/\/events\/[\w-]+\/planning$/, {
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Event name should be visible on the event page
      await expect(page.getByTestId('event-name')).toContainText(
        'Modal Test Event'
      )
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
