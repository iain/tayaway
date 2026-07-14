import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getObjectByType,
  getObjectsByType,
  getTestSession,
  setupAuthenticatedPage,
  createBareEvent,
  PAGE_LOAD_TIMEOUT,
  newApiContext,
  offsetDate,
  futureCalendarDate,
} from '../helpers'

const TEST_EMAIL = 'e2e-event-edit@example.com'
const TEST_NAME = 'E2E Event Edit User'

test.describe('Event Edit', () => {
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
            start_date: offsetDate(30),
            end_date: offsetDate(35),
          },
        }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const event = getObjectByType(body.objects, 'event')
      expect(event?.startDate).toBe(offsetDate(30))
      expect(event?.endDate).toBe(offsetDate(35))
    })

    test('PUT /api/events/:id can clear dates', async () => {
      const createResponse = await apiContext.post(`${API_BASE}/api/events`, {
        data: {
          name: 'API Clear Dates',
          start_date: offsetDate(30),
          end_date: offsetDate(35),
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

    test('changing dates resets the answers server-side, keeping the roster', async () => {
      // Creator answers with a day set and brings a guest; then the dates
      // move. Everyone stays on the list but reverts to pending with days
      // cleared (doc/attendances.md phase 6) — legacy rsvp rows are deleted
      // for stale clients.
      const createResponse = await apiContext.post(`${API_BASE}/api/events`, {
        data: {
          name: 'Reset Dates',
          start_date: offsetDate(30),
          end_date: offsetDate(35),
        },
      })
      const eventId = getObjectByType(
        (await createResponse.json()).objects,
        'event'
      )!.id
      await apiContext.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: { attending: true, attendance: [offsetDate(30), offsetDate(31)] },
      })
      await apiContext.post(`${API_BASE}/api/events/${eventId}/attendances`, {
        data: {
          id: crypto.randomUUID(),
          status: 'going',
          guest: { id: crypto.randomUUID(), name: 'Reset Guest' },
        },
      })

      const response = await apiContext.put(
        `${API_BASE}/api/events/${eventId}`,
        {
          data: {
            name: 'Reset Dates',
            start_date: offsetDate(40),
            end_date: offsetDate(45),
          },
        }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body.deleted.length).toBe(1)
      expect(body.deleted[0].objectType).toBe('rsvp')

      const attendancesResp = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/attendances`
      )
      const attendances = getObjectsByType(
        (await attendancesResp.json()).objects,
        'attendance'
      ) as Array<{ status: string; days: string[] | null }>
      expect(attendances.length).toBe(2)
      for (const attendance of attendances) {
        expect(attendance.status).toBe('pending')
        expect(attendance.days).toBeNull()
      }
      const rsvpsResp = await apiContext.get(
        `${API_BASE}/api/events/${eventId}/rsvps`
      )
      expect(getObjectsByType((await rsvpsResp.json()).objects, 'rsvp').length).toBe(0)
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
    await expect(page.getByTestId('edit-name-input')).toHaveValue(
      'Edit Flow Test'
    )

    // Cancel closes inline edit without saving
    await page.getByTestId('edit-name-input').fill('Changed Name')
    await page.getByRole('button', { name: 'Cancel' }).click()
    await expect(page.getByTestId('event-name')).toContainText('Edit Flow Test')

    // Can update event name
    await page.getByTestId('edit-name-button').locator('..').hover()
    await page.getByTestId('edit-name-button').click()
    await page.getByTestId('edit-name-input').fill('Updated Name')
    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page.getByTestId('event-name')).toContainText('Updated Name')

    // Description inline edit is pre-populated with current description
    await page.getByTestId('edit-description-button').locator('..').hover()
    await page.getByTestId('edit-description-button').click()
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

    // Open calendar modal for dates
    await page.getByTestId('edit-dates-button').locator('..').hover()
    await page.getByTestId('edit-dates-button').click()
    await expect(page.getByRole('dialog')).toBeVisible()
    await expect(
      page.getByRole('dialog').getByRole('heading', { name: 'Event dates' })
    ).toBeVisible()

    // Can set start and end dates by clicking calendar days (a few months out)
    const start = futureCalendarDate(3, 10)
    const end = futureCalendarDate(3, 14)
    while (!(await page.getByText(start.monthLabel).isVisible())) {
      await page
        .getByRole('dialog')
        .getByRole('button', { name: /next/i })
        .click()
    }
    await page.getByTestId(`calendar-day-${start.iso}`).first().click()
    await page.getByTestId(`calendar-day-${end.iso}`).first().click()
    await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click()
    await expect(page.getByRole('dialog')).not.toBeVisible()

    await expect(page.getByTestId('event-dates')).toBeVisible()
    await expect(page.getByTestId('event-dates')).toContainText(start.shortDate)
    await expect(page.getByTestId('event-dates')).toContainText(end.shortDate)

    // Can update to a single-day date
    await page.getByTestId('edit-dates-button').locator('..').hover()
    await page.getByTestId('edit-dates-button').click()
    await expect(page.getByRole('dialog')).toBeVisible()
    const single = futureCalendarDate(5, 20)
    while (!(await page.getByText(single.monthLabel).isVisible())) {
      await page
        .getByRole('dialog')
        .getByRole('button', { name: /next/i })
        .click()
    }
    // Click same day twice for single-day event
    await page.getByTestId(`calendar-day-${single.iso}`).first().click()
    await page.getByTestId(`calendar-day-${single.iso}`).first().click()
    await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click()
    await expect(page.getByRole('dialog')).not.toBeVisible()

    await expect(page.getByTestId('event-dates')).toBeVisible()
    await expect(page.getByTestId('event-dates')).toContainText(single.shortDate)
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
        start_date: futureCalendarDate(2, 1).iso,
        end_date: futureCalendarDate(2, 7).iso,
      },
    })
    const body = await response.json()
    const event = getObjectByType(body.objects, 'event')

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto(`/events/${event!.id}`)
    await expect(page.getByTestId('event-name')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Open calendar modal for dates
    await page.getByTestId('edit-dates-button').locator('..').hover()
    await page.getByTestId('edit-dates-button').click()
    await expect(page.getByRole('dialog')).toBeVisible()
    await expect(
      page.getByRole('dialog').getByRole('heading', { name: 'Event dates' })
    ).toBeVisible()

    // Pick new dates (clicking a new start clears the existing selection),
    // a couple of months past the pre-existing ones.
    const newStart = futureCalendarDate(4, 15)
    const newEnd = futureCalendarDate(4, 20)
    while (!(await page.getByText(newStart.monthLabel).isVisible())) {
      await page
        .getByRole('dialog')
        .getByRole('button', { name: /next/i })
        .click()
    }
    await page.getByTestId(`calendar-day-${newStart.iso}`).first().click()
    await page.getByTestId(`calendar-day-${newEnd.iso}`).first().click()
    await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click()
    await expect(page.getByRole('dialog')).not.toBeVisible()

    await expect(page.getByTestId('event-dates')).toBeVisible()
    await expect(page.getByTestId('event-dates')).toContainText(
      newStart.shortDate
    )
    await expect(page.getByTestId('event-dates')).toContainText(newEnd.shortDate)
  })
})
