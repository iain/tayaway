import { test, expect } from '@playwright/test'
import {
  API_BASE,
  getObjectByType,
  getTestSession,
  newApiContext,
  setupAuthenticatedPage,
  PAGE_LOAD_TIMEOUT,
} from '../helpers'

/**
 * Local-time ISO date (YYYY-MM-DD) offset by `days`. The homepage chore window
 * reckons "today"/"tomorrow" in the viewer's local zone (chore times are local
 * wall-clock), so fixtures must build their dates from local parts too.
 */
function localDate(days: number): string {
  const d = new Date()
  d.setDate(d.getDate() + days)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

test.describe('Homepage upcoming chores', () => {
  test('surfaces a chore during an event and links to the roster', async ({
    page,
    playwright,
  }) => {
    const apiContext = await newApiContext(playwright)
    const uid = Date.now()
    // A fresh user (and thus a clean workspace) so the section shows only this
    // test's chore — no leakage from other tests sharing the database.
    const { token, userId } = await getTestSession(
      apiContext,
      `e2e-home-chores-${uid}@example.com`,
      'Home Chores User'
    )

    // A current event spanning today. The range is deliberately wide so the
    // event is "current" under both the UTC reckoning the events list uses and
    // the local reckoning the chore window uses.
    const eventResp = await apiContext.post(`${API_BASE}/api/events`, {
      data: {
        name: `Lake House ${uid}`,
        start_date: localDate(-1),
        end_date: localDate(2),
      },
    })
    const eventId = getObjectByType((await eventResp.json()).objects, 'event')!
      .id

    // RSVP attending so the user can hold a chore assignment.
    await apiContext.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
      data: { attending: true },
    })

    const rosterResp = await apiContext.post(`${API_BASE}/api/chore-rosters`, {
      data: { event_id: eventId },
    })
    const rosterId = getObjectByType(
      (await rosterResp.json()).objects,
      'choreRoster'
    )!.id

    // An untimed chore stays "upcoming" for the whole of today, so the test is
    // immune to what time of day it runs.
    const choreResp = await apiContext.post(
      `${API_BASE}/api/chore-rosters/${rosterId}/chores`,
      { data: { name: `Dishes ${uid}`, people_per_day: 1 } }
    )
    const choreId = getObjectByType((await choreResp.json()).objects, 'chore')!
      .id

    const assignResp = await apiContext.post(
      `${API_BASE}/api/chore-rosters/${rosterId}/assignments`,
      { data: { chore_id: choreId, user_id: userId, date: localDate(0) } }
    )
    expect(assignResp.status()).toBe(201)

    await setupAuthenticatedPage(page, token)
    await page.goto('/')

    const section = page.getByTestId('upcoming-chores-section')
    await expect(section).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
    await expect(section.getByText(`Dishes ${uid}`)).toBeVisible()
    await expect(section.getByText(`Lake House ${uid}`)).toBeVisible()

    // The chore links through to its event's roster.
    await section.getByText(`Dishes ${uid}`).click()
    await expect(page).toHaveURL(`/events/${eventId}/chores`)

    await apiContext.dispose()
  })
})
