import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getTestSession,
  setupAuthenticatedPage,
  createResolvedEvent,
  getObjectByType,
  getWorkspaceId,
  addMemberToWorkspace,
  PAGE_LOAD_TIMEOUT,
  newApiContext,
  RESOLVED_EVENT_START,
} from '../helpers'

// Add whole days to an ISO date, UTC-anchored to stay DST-proof.
function isoAddDays(iso: string, days: number): string {
  const date = new Date(`${iso}T00:00:00Z`)
  date.setUTCDate(date.getUTCDate() + days)
  return date.toISOString().slice(0, 10)
}

const TEST_EMAIL = 'e2e-days@example.com'
const TEST_NAME = 'E2E Days User'
const BOB_EMAIL = 'e2e-days-bob@example.com'
const CAROL_EMAIL = 'e2e-days-carol@example.com'

async function createRoster(
  request: APIRequestContext,
  eventId: string
): Promise<string> {
  const response = await request.post(`${API_BASE}/api/chore-rosters`, {
    data: { event_id: eventId },
  })
  expect(response.status()).toBe(201)
  const body = await response.json()
  return getObjectByType(body.objects, 'choreRoster')!.id
}

async function addChore(
  request: APIRequestContext,
  rosterId: string,
  name: string
): Promise<string> {
  const response = await request.post(
    `${API_BASE}/api/chore-rosters/${rosterId}/chores`,
    { data: { name, people_per_day: 1 } }
  )
  expect(response.status()).toBe(201)
  const body = await response.json()
  return getObjectByType(body.objects, 'chore')!.id
}

test.describe('Days page', () => {
  let sessionToken: string
  let aliceId: string
  let apiContext: APIRequestContext

  test.beforeAll(async ({ playwright }) => {
    apiContext = await newApiContext(playwright)
    const { token, userId } = await getTestSession(
      apiContext,
      TEST_EMAIL,
      TEST_NAME
    )
    sessionToken = token
    aliceId = userId
  })

  test.afterAll(async () => {
    await apiContext.dispose()
  })

  test('shows per-day headcounts, comings and goings, and chore duties', async ({
    page,
    playwright,
  }) => {
    // Alice (creator) is auto-RSVP'd for the whole 7-day event.
    const { eventId } = await createResolvedEvent(apiContext, 'Days breakdown')
    const d = (offset: number) => isoAddDays(RESOLVED_EVENT_START, offset)
    const workspaceId = await getWorkspaceId(apiContext)

    // Bob comes and goes: days 1 and 2, bringing a named guest on day 1.
    const bobContext = await newApiContext(playwright)
    await getTestSession(bobContext, BOB_EMAIL, 'Days Bob')
    await addMemberToWorkspace(apiContext, workspaceId, BOB_EMAIL)
    await bobContext.post(`${API_BASE}/api/events/${eventId}/attendances`, {
      data: { id: crypto.randomUUID(), status: 'going', days: [d(1), d(2)] },
    })
    await bobContext.post(`${API_BASE}/api/events/${eventId}/attendances`, {
      data: {
        id: crypto.randomUUID(),
        status: 'going',
        days: [d(1)],
        guest: { id: crypto.randomUUID(), name: "Bob's +1" },
      },
    })
    await bobContext.dispose()

    // Carol never responds — the pending note's subject.
    const carolContext = await newApiContext(playwright)
    await getTestSession(carolContext, CAROL_EMAIL, 'Days Carol')
    await carolContext.dispose()
    await addMemberToWorkspace(apiContext, workspaceId, CAROL_EMAIL)

    // Alice cooks on day 1 — the duty shown beside that day's count.
    const rosterId = await createRoster(apiContext, eventId)
    const choreId = await addChore(apiContext, rosterId, 'Cooking')
    await apiContext.post(
      `${API_BASE}/api/chore-rosters/${rosterId}/assignments`,
      { data: { chore_id: choreId, user_id: aliceId, date: d(1) } }
    )

    // Reach the page the way a user would: RSVP page → Days tab.
    await setupAuthenticatedPage(page, sessionToken)
    await page.goto(`/events/${eventId}/rsvp`)
    await expect(page.getByTestId('event-name')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
    await page
      .getByTestId('event-tabs')
      .getByRole('link', { name: 'Days' })
      .click()
    await expect(page.getByTestId('days-list')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Headcounts: Alice alone; Alice + Bob + guest; Alice + Bob; Alice alone.
    await expect(page.getByTestId(`days-headcount-${d(0)}`)).toHaveText(
      /1\s*person/
    )
    await expect(page.getByTestId(`days-headcount-${d(1)}`)).toHaveText(
      /3\s*2 \+ 1 guest/
    )
    await expect(page.getByTestId(`days-headcount-${d(2)}`)).toHaveText(
      /2\s*people/
    )
    await expect(page.getByTestId(`days-headcount-${d(3)}`)).toHaveText(
      /1\s*person/
    )

    // Bob arrives on day 1 and day 2 is his last; Alice, there throughout,
    // never shows up as comings-and-goings chatter.
    await expect(page.getByTestId(`days-arrivals-${d(1)}`)).toContainText(
      'Days Bob'
    )
    await expect(page.getByTestId(`days-departures-${d(2)}`)).toContainText(
      'Days Bob'
    )
    await expect(page.getByTestId(`days-arrivals-${d(2)}`)).not.toBeVisible()

    // The cooking duty sits inside day 1's section.
    const day1 = page.locator(`[data-date="${d(1)}"]`)
    await expect(day1).toContainText('Cooking')
    await expect(day1).toContainText(TEST_NAME)

    // Carol hasn't responded, so the counts carry a lower-bound caveat.
    await expect(page.getByTestId('days-pending-note')).toContainText(
      '1 member hasn’t responded yet'
    )
  })
})
