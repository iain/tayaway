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

  test.describe('Edit buttons', () => {
    test('edit buttons are visible on the event page for the owner', async ({
      page,
    }) => {
      const eventId = await createBareEvent(
        apiContext,
        'Button Visibility Test'
      )
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await expect(page.getByTestId('edit-name-button')).toBeAttached()
      await expect(page.getByTestId('edit-description-button')).toBeAttached()
      await expect(page.getByTestId('edit-dates-button')).toBeAttached()
    })
  })

  test.describe('Form pre-population', () => {
    test('name modal is pre-populated with current event name', async ({
      page,
    }) => {
      const eventId = await createBareEvent(apiContext, 'Prepopulate Test')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page.getByTestId('edit-name-button').click({ force: true })
      await expect(page.getByTestId('edit-name-input')).toHaveValue(
        'Prepopulate Test'
      )
    })

    test('description modal is pre-populated with current description', async ({
      page,
    }) => {
      const eventId = await createBareEvent(apiContext, 'Desc Prepopulate Test')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page.getByTestId('edit-description-button').click({ force: true })
      await expect(page.getByTestId('edit-description-input')).toHaveValue(
        'Test event'
      )
    })

    test('date fields are empty when event has no dates', async ({ page }) => {
      const eventId = await createBareEvent(apiContext)
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page.getByTestId('edit-dates-button').click({ force: true })
      await expect(page.getByTestId('edit-start-date-input')).toHaveValue('')
      await expect(page.getByTestId('edit-end-date-input')).toHaveValue('')
    })

    test('date fields are pre-populated when event has dates', async ({
      page,
    }) => {
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
      await page.goto(`/events/${event!.id}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page.getByTestId('edit-dates-button').click({ force: true })
      await expect(page.getByTestId('edit-start-date-input')).toHaveValue(
        '2026-08-01'
      )
      await expect(page.getByTestId('edit-end-date-input')).toHaveValue(
        '2026-08-07'
      )
    })
  })

  test.describe('Editing event name', () => {
    test('can update event name', async ({ page }) => {
      const eventId = await createBareEvent(apiContext, 'Original Name')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page.getByTestId('edit-name-button').click({ force: true })
      await page.getByTestId('edit-name-input').fill('Updated Name')
      await page.getByTestId('submit-button').click()

      await expect(page.getByTestId('event-name')).toContainText('Updated Name')
    })
  })

  test.describe('Setting event dates', () => {
    test('can set start and end dates and save', async ({ page }) => {
      const eventId = await createBareEvent(apiContext, 'Set Dates Event')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page.getByTestId('edit-dates-button').click({ force: true })
      await page.getByTestId('edit-start-date-input').fill('2026-09-01')
      await page.getByTestId('edit-end-date-input').fill('2026-09-05')
      await page.getByTestId('submit-button').click()

      await expect(page.getByTestId('event-dates')).toBeVisible()
      await expect(page.getByTestId('event-dates')).toContainText(/Sep 1/)
      await expect(page.getByTestId('event-dates')).toContainText(/Sep 5/)
    })

    test('can update existing dates', async ({ page }) => {
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
      await page.goto(`/events/${event!.id}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page.getByTestId('edit-dates-button').click({ force: true })
      await page.getByTestId('edit-start-date-input').fill('2026-10-15')
      await page.getByTestId('edit-end-date-input').fill('2026-10-20')
      await page.getByTestId('submit-button').click()

      await expect(page.getByTestId('event-dates')).toBeVisible()
      await expect(page.getByTestId('event-dates')).toContainText(/Oct 15/)
      await expect(page.getByTestId('event-dates')).toContainText(/Oct 20/)
    })

    test('can set a single-day event date', async ({ page }) => {
      const eventId = await createBareEvent(apiContext, 'Single Day Event')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page.getByTestId('edit-dates-button').click({ force: true })
      await page.getByTestId('edit-start-date-input').fill('2026-12-25')
      await page.getByTestId('edit-end-date-input').fill('2026-12-25')
      await page.getByTestId('submit-button').click()

      await expect(page.getByTestId('event-dates')).toBeVisible()
      await expect(page.getByTestId('event-dates')).toContainText(/Dec 25/)
    })
  })

  test.describe('Clearing event dates', () => {
    test('can clear dates by emptying the fields', async ({ page }) => {
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
      await page.goto(`/events/${event!.id}`)
      await expect(page.getByTestId('event-dates')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page.getByTestId('edit-dates-button').click({ force: true })
      await page.getByTestId('edit-start-date-input').fill('')
      await page.getByTestId('edit-end-date-input').fill('')
      await page.getByTestId('submit-button').click()

      await expect(page.getByTestId('event-dates')).not.toBeVisible()
    })
  })

  test.describe('Cancel', () => {
    test('cancel closes modal without saving', async ({ page }) => {
      const eventId = await createBareEvent(apiContext, 'Cancel Test Event')
      await setupAuthenticatedPage(page, sessionToken)

      await page.goto(`/events/${eventId}`)
      await expect(page.getByTestId('event-name')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      await page.getByTestId('edit-name-button').click({ force: true })
      await page.getByTestId('edit-name-input').fill('Changed Name')
      await page.getByTestId('cancel-button').click()

      await expect(page.getByTestId('event-name')).toContainText(
        'Cancel Test Event'
      )
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
})
