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
 * ISO date (YYYY-MM-DD) offset by `days`, computed in UTC. The homepage chore
 * window reckons "today"/"tomorrow" in the event's own zone, and the event below
 * is pinned to UTC — so building fixtures in UTC keeps them on the same calendar
 * day no matter when, or in which timezone, the suite runs. (Building them in the
 * process-local zone disagreed with the event's zone whenever CI ran between
 * 22:00–24:00 UTC — past midnight in CET/CEST — dropping the chore a day.)
 */
function utcDate(days: number): string {
  const d = new Date()
  d.setUTCDate(d.getUTCDate() + days)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`
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

    // A current event spanning today, pinned to UTC so the chore window (which
    // reckons "today" in the event's zone) agrees with the UTC fixture dates.
    // The range is deliberately wide so the event is also "current" under the
    // UTC reckoning the events list uses.
    const eventResp = await apiContext.post(`${API_BASE}/api/events`, {
      data: {
        name: `Lake House ${uid}`,
        start_date: utcDate(-1),
        end_date: utcDate(2),
        timezone: 'UTC',
      },
    })
    const eventId = getObjectByType((await eventResp.json()).objects, 'event')!
      .id

    // RSVP attending so the user can hold a chore assignment.
    await apiContext.post(`${API_BASE}/api/events/${eventId}/attendances`, {
      data: { status: 'going' },
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
      { data: { chore_id: choreId, user_id: userId, date: utcDate(0) } }
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
