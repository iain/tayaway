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

test.describe('Event Edit Page', () => {
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

  test.describe('Navigation', () => {
    test('"Edit Event" button navigates to edit page', async ({ page }) => {
      const eventId = await createBareEvent(apiContext, 'Nav Test Event')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page.getByRole('button', { name: 'Edit Event' }).click()
      await expect(page).toHaveURL(`/events/${eventId}/edit`)
    })

    test('edit page shows "Edit Event" heading', async ({ page }) => {
      const eventId = await createBareEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/edit`)
      await expect(
        page.getByRole('heading', { name: 'Edit Event' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
    })
  })

  test.describe('Form pre-population', () => {
    test('form is pre-populated with current event data', async ({ page }) => {
      const eventId = await createBareEvent(apiContext, 'Prepopulate Test')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/edit`)
      await expect(
        page.getByRole('heading', { name: 'Edit Event' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await expect(page.getByTestId('event-name-input')).toHaveValue(
        'Prepopulate Test'
      )
      await expect(page.getByTestId('event-description-input')).toHaveValue(
        'Test event'
      )
    })

    test('date fields are empty when event has no dates', async ({ page }) => {
      const eventId = await createBareEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/edit`)
      await expect(
        page.getByRole('heading', { name: 'Edit Event' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await expect(page.getByTestId('event-start-date-input')).toHaveValue('')
      await expect(page.getByTestId('event-end-date-input')).toHaveValue('')
    })

    test('date fields are pre-populated when event has dates', async ({
      page,
    }) => {
      // Create event with dates via API
      const response = await apiContext.post(`${API_BASE}/api/events`, {
        data: {
          name: 'Dated Event',
          start_date: '2026-08-01',
          end_date: '2026-08-07',
        },
      })
      const body = await response.json()
      const event = getObjectByType(body.objects, 'event')

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${event!.id}/edit`)
      await expect(
        page.getByRole('heading', { name: 'Edit Event' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await expect(page.getByTestId('event-start-date-input')).toHaveValue(
        '2026-08-01'
      )
      await expect(page.getByTestId('event-end-date-input')).toHaveValue(
        '2026-08-07'
      )
    })
  })

  test.describe('Setting event dates', () => {
    test('can set start and end dates and save', async ({ page }) => {
      const eventId = await createBareEvent(apiContext, 'Set Dates Event')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/edit`)
      await expect(
        page.getByRole('heading', { name: 'Edit Event' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Fill in dates
      await page.getByTestId('event-start-date-input').fill('2026-09-01')
      await page.getByTestId('event-end-date-input').fill('2026-09-05')

      // Save
      await page.getByTestId('submit-button').click()

      // Should redirect to event page
      await expect(page).toHaveURL(`/events/${eventId}`, {
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Dates should display on the event page
      await expect(page.getByTestId('event-dates')).toBeVisible()
      await expect(page.getByTestId('event-dates')).toContainText(/Sep 1/)
      await expect(page.getByTestId('event-dates')).toContainText(/Sep 5/)
    })

    test('can update existing dates', async ({ page }) => {
      // Create event with dates
      const response = await apiContext.post(`${API_BASE}/api/events`, {
        data: {
          name: 'Update Dates Event',
          start_date: '2026-07-01',
          end_date: '2026-07-05',
        },
      })
      const body = await response.json()
      const event = getObjectByType(body.objects, 'event')

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${event!.id}/edit`)
      await expect(
        page.getByRole('heading', { name: 'Edit Event' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Change dates
      await page.getByTestId('event-start-date-input').fill('2026-10-15')
      await page.getByTestId('event-end-date-input').fill('2026-10-20')

      // Save
      await page.getByTestId('submit-button').click()

      // Should redirect and show new dates
      await expect(page).toHaveURL(`/events/${event!.id}`, {
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(page.getByTestId('event-dates')).toBeVisible()
      await expect(page.getByTestId('event-dates')).toContainText(/Oct 15/)
      await expect(page.getByTestId('event-dates')).toContainText(/Oct 20/)
    })

    test('can set a single-day event date', async ({ page }) => {
      const eventId = await createBareEvent(apiContext, 'Single Day Event')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/edit`)
      await expect(
        page.getByRole('heading', { name: 'Edit Event' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Set same start and end date
      await page.getByTestId('event-start-date-input').fill('2026-12-25')
      await page.getByTestId('event-end-date-input').fill('2026-12-25')

      await page.getByTestId('submit-button').click()
      await expect(page).toHaveURL(`/events/${eventId}`, {
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Should display the date (only once, since start === end)
      await expect(page.getByTestId('event-dates')).toBeVisible()
      await expect(page.getByTestId('event-dates')).toContainText(/Dec 25/)
    })
  })

  test.describe('Clearing event dates', () => {
    test('can clear dates by emptying the fields', async ({ page }) => {
      // Create event with dates
      const response = await apiContext.post(`${API_BASE}/api/events`, {
        data: {
          name: 'Clear Dates Event',
          start_date: '2026-11-01',
          end_date: '2026-11-05',
        },
      })
      const body = await response.json()
      const event = getObjectByType(body.objects, 'event')

      await setupAuthenticatedPage(page, sessionToken)

      // Verify dates show on event page first
      await page.goto(`/events/${event!.id}`)
      await expect(page.getByTestId('event-dates')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Navigate to edit page
      await page.getByRole('button', { name: 'Edit Event' }).click()
      await expect(page).toHaveURL(`/events/${event!.id}/edit`)
      await expect(
        page.getByRole('heading', { name: 'Edit Event' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Clear dates
      await page.getByTestId('event-start-date-input').fill('')
      await page.getByTestId('event-end-date-input').fill('')

      // Save
      await page.getByTestId('submit-button').click()
      await expect(page).toHaveURL(`/events/${event!.id}`, {
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Dates should no longer be displayed
      await expect(page.getByTestId('event-dates')).not.toBeVisible()
    })
  })

  test.describe('Cancel and validation', () => {
    test('cancel returns to event page without saving', async ({ page }) => {
      const eventId = await createBareEvent(apiContext, 'Cancel Test Event')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/edit`)
      await expect(
        page.getByRole('heading', { name: 'Edit Event' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Change the name
      await page.getByTestId('event-name-input').fill('Changed Name')

      // Cancel
      await page.getByTestId('cancel-button').click()

      // Should return to event page with original name
      await expect(page).toHaveURL(`/events/${eventId}`, {
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(page.getByTestId('event-name')).toContainText(
        'Cancel Test Event'
      )
    })

    test('can update event name along with dates', async ({ page }) => {
      const eventId = await createBareEvent(apiContext, 'Name And Dates Event')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}/edit`)
      await expect(
        page.getByRole('heading', { name: 'Edit Event' })
      ).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Update name and add dates
      await page.getByTestId('event-name-input').fill('Updated Event Name')
      await page.getByTestId('event-start-date-input').fill('2026-08-15')
      await page.getByTestId('event-end-date-input').fill('2026-08-20')

      await page.getByTestId('submit-button').click()
      await expect(page).toHaveURL(`/events/${eventId}`, {
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Both name and dates should be updated
      await expect(page.getByTestId('event-name')).toContainText(
        'Updated Event Name'
      )
      await expect(page.getByTestId('event-dates')).toBeVisible()
      await expect(page.getByTestId('event-dates')).toContainText(/Aug 15/)
      await expect(page.getByTestId('event-dates')).toContainText(/Aug 20/)
    })
  })

  test.describe('Event Edit API', () => {
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
      // Create event with dates
      const createResponse = await apiContext.post(`${API_BASE}/api/events`, {
        data: {
          name: 'API Clear Dates',
          start_date: '2026-06-15',
          end_date: '2026-06-20',
        },
      })
      const createBody = await createResponse.json()
      const createdEvent = getObjectByType(createBody.objects, 'event')

      // Clear dates by sending empty strings
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
})
