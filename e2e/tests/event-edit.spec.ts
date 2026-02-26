import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getObjectByType,
  getTestSession,
  setupAuthenticatedPage,
  createBareEvent,
  PAGE_LOAD_TIMEOUT,
} from '../helpers'

const TEST_EMAIL = 'e2e-event-edit@example.com'
const TEST_NAME = 'E2E Event Edit User'

test.describe('Event Edit', () => {
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

  test.describe('Event Edit API', () => {
    test('PUT /api/events/:id sets and clears location', async () => {
      const eventId = await createBareEvent(apiContext, 'API Location Event')

      // Set location (requires coordinates alongside location_name)
      const setResponse = await apiContext.put(
        `${API_BASE}/api/events/${eventId}`,
        {
          data: {
            name: 'API Location Event',
            location_name: 'Berlin, Germany',
            latitude: 52.52,
            longitude: 13.405,
          },
        }
      )
      expect(setResponse.ok()).toBeTruthy()
      const setBody = await setResponse.json()
      const updated = getObjectByType(setBody.objects, 'event')
      expect(updated?.locationName).toBe('Berlin, Germany')

      // Clear location
      const clearResponse = await apiContext.put(
        `${API_BASE}/api/events/${eventId}`,
        {
          data: {
            name: 'API Location Event',
            location_name: '',
          },
        }
      )
      expect(clearResponse.ok()).toBeTruthy()
      const clearBody = await clearResponse.json()
      const cleared = getObjectByType(clearBody.objects, 'event')
      expect(cleared?.locationName).toBeNull()
    })

    test('PUT /api/events/:id updates dates', async () => {
      const eventId = await createBareEvent(apiContext, 'API Dates Event')

      const response = await apiContext.put(
        `${API_BASE}/api/events/${eventId}`,
        {
          data: {
            name: 'API Dates Event',
            start_date: '2026-06-15',
            end_date: '2026-06-20',
          },
        }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const event = getObjectByType(body.objects, 'event')
      expect(event?.startDate).toBe('2026-06-15')
      expect(event?.endDate).toBe('2026-06-20')
    })

    test('PUT /api/events/:id can clear dates', async () => {
      const createResponse = await apiContext.post(`${API_BASE}/api/events`, {
        data: {
          name: 'API Clear Dates',
          start_date: '2026-06-15',
          end_date: '2026-06-20',
        },
      })
      const createBody = await createResponse.json()
      const createdEvent = getObjectByType(createBody.objects, 'event')

      const response = await apiContext.put(
        `${API_BASE}/api/events/${createdEvent!.id}`,
        {
          data: {
            name: 'API Clear Dates',
            start_date: '',
            end_date: '',
          },
        }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const event = getObjectByType(body.objects, 'event')
      expect(event?.startDate).toBeNull()
      expect(event?.endDate).toBeNull()
    })
  })

  test('edit name and description flow', async ({ page }) => {
    const eventId = await createBareEvent(apiContext, 'Edit Flow Test')
    await setupAuthenticatedPage(page, sessionToken)

    await page.goto(`/events/${eventId}`)
    await expect(page.getByTestId('event-name')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // All edit buttons are visible for the owner
    await expect(page.getByTestId('edit-name-button')).toBeAttached()
    await expect(page.getByTestId('edit-description-button')).toBeAttached()
    await expect(page.getByTestId('edit-dates-button')).toBeAttached()

    // Hover the group to reveal the hidden edit button, then click
    await page.getByTestId('edit-name-button').locator('..').hover()
    await page.getByTestId('edit-name-button').click()
    await expect(page.getByRole('dialog')).toBeVisible()
    await expect(page.getByTestId('edit-name-input')).toHaveValue(
      'Edit Flow Test'
    )

    // Cancel closes modal without saving
    await page.getByTestId('edit-name-input').fill('Changed Name')
    await page.getByTestId('cancel-button').click()
    await expect(page.getByRole('dialog')).not.toBeVisible()
    await expect(page.getByTestId('event-name')).toContainText('Edit Flow Test')

    // Can update event name
    await page.getByTestId('edit-name-button').locator('..').hover()
    await page.getByTestId('edit-name-button').click()
    await expect(page.getByRole('dialog')).toBeVisible()
    await page.getByTestId('edit-name-input').fill('Updated Name')
    await page.getByTestId('submit-button').click()
    await expect(page.getByRole('dialog')).not.toBeVisible()
    await expect(page.getByTestId('event-name')).toContainText('Updated Name')

    // Description modal is pre-populated with current description
    await page.getByTestId('edit-description-button').locator('..').hover()
    await page.getByTestId('edit-description-button').click()
    await expect(page.getByRole('dialog')).toBeVisible()
    await expect(page.getByTestId('edit-description-input')).toHaveValue(
      'Test event'
    )
  })

  test('date editing from scratch: set, single-day, and clear', async ({
    page,
  }) => {
    const eventId = await createBareEvent(apiContext, 'Date Scratch Event')
    await setupAuthenticatedPage(page, sessionToken)

    await page.goto(`/events/${eventId}`)
    await expect(page.getByTestId('event-name')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Date fields are empty when event has no dates
    await page.getByTestId('edit-dates-button').locator('..').hover()
    await page.getByTestId('edit-dates-button').click()
    await expect(page.getByRole('dialog')).toBeVisible()
    await expect(page.getByTestId('edit-start-date-input')).toHaveValue('')
    await expect(page.getByTestId('edit-end-date-input')).toHaveValue('')

    // Can set start and end dates
    await page.getByTestId('edit-start-date-input').fill('2026-09-01')
    await page.getByTestId('edit-end-date-input').fill('2026-09-05')
    await page.getByTestId('submit-button').click()
    await expect(page.getByRole('dialog')).not.toBeVisible()

    await expect(page.getByTestId('event-dates')).toBeVisible()
    await expect(page.getByTestId('event-dates')).toContainText(/Sep 1/)
    await expect(page.getByTestId('event-dates')).toContainText(/Sep 5/)

    // Can update to a single-day date
    await page.getByTestId('edit-dates-button').locator('..').hover()
    await page.getByTestId('edit-dates-button').click()
    await expect(page.getByRole('dialog')).toBeVisible()
    await page.getByTestId('edit-start-date-input').fill('2026-12-25')
    await page.getByTestId('edit-end-date-input').fill('2026-12-25')
    await page.getByTestId('submit-button').click()
    await expect(page.getByRole('dialog')).not.toBeVisible()

    await expect(page.getByTestId('event-dates')).toBeVisible()
    await expect(page.getByTestId('event-dates')).toContainText(/Dec 25/)

    // Can clear dates by emptying the fields
    await page.getByTestId('edit-dates-button').locator('..').hover()
    await page.getByTestId('edit-dates-button').click()
    await expect(page.getByRole('dialog')).toBeVisible()
    await page.getByTestId('edit-start-date-input').fill('')
    await page.getByTestId('edit-end-date-input').fill('')
    await page.getByTestId('submit-button').click()

    await expect(page.getByTestId('event-dates')).not.toBeVisible()
  })

  test('location set via API is displayed on event page', async ({ page }) => {
    // Create event with location set via API (coordinates required)
    const response = await apiContext.post(`${API_BASE}/api/events`, {
      data: {
        name: 'Location Display Test',
        location_name: 'Amsterdam, Netherlands',
        latitude: 52.3676,
        longitude: 4.9041,
      },
    })
    const body = await response.json()
    const event = getObjectByType(body.objects, 'event')

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto(`/events/${event!.id}`)
    await expect(page.getByTestId('event-name')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Location should be displayed on the event page
    await expect(page.getByText('Amsterdam, Netherlands')).toBeVisible()
  })

  test('date editing with pre-existing dates', async ({ page }) => {
    const response = await apiContext.post(`${API_BASE}/api/events`, {
      data: {
        name: 'Pre-dated Event',
        start_date: '2026-08-01',
        end_date: '2026-08-07',
      },
    })
    const body = await response.json()
    const event = getObjectByType(body.objects, 'event')

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto(`/events/${event!.id}`)
    await expect(page.getByTestId('event-name')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Date fields are pre-populated with existing dates
    await page.getByTestId('edit-dates-button').locator('..').hover()
    await page.getByTestId('edit-dates-button').click()
    await expect(page.getByRole('dialog')).toBeVisible()
    await expect(page.getByTestId('edit-start-date-input')).toHaveValue(
      '2026-08-01'
    )
    await expect(page.getByTestId('edit-end-date-input')).toHaveValue(
      '2026-08-07'
    )

    // Can update existing dates
    await page.getByTestId('edit-start-date-input').fill('2026-10-15')
    await page.getByTestId('edit-end-date-input').fill('2026-10-20')
    await page.getByTestId('submit-button').click()
    await expect(page.getByRole('dialog')).not.toBeVisible()

    await expect(page.getByTestId('event-dates')).toBeVisible()
    await expect(page.getByTestId('event-dates')).toContainText(/Oct 15/)
    await expect(page.getByTestId('event-dates')).toContainText(/Oct 20/)
  })
})
