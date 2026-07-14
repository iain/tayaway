import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getTestSession,
  setupAuthenticatedPage,
  createResolvedEvent,
  getObjectsByType,
  getWorkspaceId,
  PAGE_LOAD_TIMEOUT,
  newApiContext,
  RESOLVED_EVENT_END,
} from '../helpers'

const TEST_EMAIL = 'e2e-guests@example.com'
const TEST_NAME = 'E2E Guests User'

test.describe('Named guests', () => {
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

  async function eventAttendances(eventId: string) {
    const resp = await apiContext.get(
      `${API_BASE}/api/events/${eventId}/attendances`
    )
    return getObjectsByType((await resp.json()).objects, 'attendance') as Array<{
      id: string
      userId: string | null
      guestId: string | null
      hostUserId: string | null
      status: string
      days: string[] | null
    }>
  }

  test('adding a named guest with picked days shows them as attending', async ({
    page,
  }) => {
    const { eventId } = await createResolvedEvent(apiContext, 'Guest add')
    await setupAuthenticatedPage(page, sessionToken)
    await page.goto(`/events/${eventId}/rsvp`)
    await expect(page.getByTestId('rsvp-section')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Open the add-guest modal, name the guest, and drop the last day so the
    // guest gets an explicit day set.
    await page.getByTestId('rsvp-add-guest').click()
    await page.getByTestId('guest-name-input').fill('Emma')
    await page.getByTestId(`calendar-day-${RESOLVED_EVENT_END}`).click()

    const [postResponse] = await Promise.all([
      page.waitForResponse(
        (resp) =>
          resp.url().includes(`/api/events/${eventId}/attendances`) &&
          resp.request().method() === 'POST'
      ),
      page.getByTestId('guest-save').click(),
    ])
    expect(postResponse.ok()).toBeTruthy()

    // Emma appears in the attending list, attributed to her host.
    const guestRow = page
      .getByTestId('attendance-guest-row')
      .filter({ hasText: 'Emma' })
    await expect(guestRow).toBeVisible()
    await expect(guestRow).toContainText(`guest of ${TEST_NAME}`)

    // Backend stored one member row and one going guest row with the day set.
    const attendances = await eventAttendances(eventId)
    const guestAttendance = attendances.find((a) => a.guestId !== null)!
    expect(guestAttendance.status).toBe('going')
    expect(guestAttendance.days).not.toBeNull()
    expect(guestAttendance.days).not.toContain(RESOLVED_EVENT_END)
    expect(guestAttendance.days!.length).toBe(6)

    // The guest has a persistent workspace identity.
    const workspaceId = await getWorkspaceId(apiContext)
    const guestsResp = await apiContext.get(
      `${API_BASE}/api/workspaces/${workspaceId}/guests`
    )
    const guests = getObjectsByType(
      (await guestsResp.json()).objects,
      'guest'
    ) as Array<{ name: string; placeholder: boolean }>
    expect(guests.some((g) => g.name === 'Emma' && !g.placeholder)).toBe(true)
  })

  test('declining is blocked while your guests are going; removing them unblocks and keeps their identity', async ({
    page,
  }) => {
    const { eventId } = await createResolvedEvent(apiContext, 'Guest decline')
    await apiContext.post(`${API_BASE}/api/events/${eventId}/attendances`, {
      data: {
        id: crypto.randomUUID(),
        status: 'going',
        guest: { id: crypto.randomUUID(), name: 'Milo' },
      },
    })

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto(`/events/${eventId}/rsvp`)
    await expect(page.getByTestId('rsvp-section')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Declining while hosting a going guest is blocked with an explanation.
    await page.getByTestId('rsvp-decline').click()
    await expect(
      page.getByText('You have guests going on this event')
    ).toBeVisible()
    await page.getByRole('button', { name: 'Cancel' }).click()
    await expect(page.getByTestId('rsvp-attend')).toHaveAttribute(
      'aria-pressed',
      'true'
    )

    // Remove the guest — same verb as declining them.
    const guestRow = page
      .getByTestId('attendance-guest-row')
      .filter({ hasText: 'Milo' })
    await guestRow.getByTestId('guest-remove').click()
    await expect(guestRow).not.toBeVisible()

    // Now the decline goes through.
    await page.getByTestId('rsvp-decline').click()
    await expect(page.getByTestId('rsvp-decline')).toHaveAttribute(
      'aria-pressed',
      'true'
    )

    // The guest row flipped to declined (not deleted), and Milo keeps his
    // workspace identity for the next trip.
    const attendances = await eventAttendances(eventId)
    const guestAttendance = attendances.find((a) => a.guestId !== null)!
    expect(guestAttendance.status).toBe('declined')
    const workspaceId = await getWorkspaceId(apiContext)
    const guestsResp = await apiContext.get(
      `${API_BASE}/api/workspaces/${workspaceId}/guests`
    )
    const guests = getObjectsByType(
      (await guestsResp.json()).objects,
      'guest'
    ) as Array<{ name: string }>
    expect(guests.some((g) => g.name === 'Milo')).toBe(true)
  })

  test('re-adding a removed guest from the picker revives the same attendance row', async ({
    page,
  }) => {
    const { eventId } = await createResolvedEvent(apiContext, 'Guest re-add')
    const guestId = crypto.randomUUID()
    await apiContext.post(`${API_BASE}/api/events/${eventId}/attendances`, {
      data: {
        id: crypto.randomUUID(),
        status: 'going',
        guest: { id: guestId, name: 'Nora' },
      },
    })
    const before = await eventAttendances(eventId)
    const originalRow = before.find((a) => a.guestId === guestId)!
    await apiContext.post(`${API_BASE}/api/events/${eventId}/attendances`, {
      data: { id: crypto.randomUUID(), status: 'declined', guest_id: guestId },
    })

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto(`/events/${eventId}/rsvp`)
    await expect(page.getByTestId('rsvp-section')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Nora is offered among existing guests — no retyping her name.
    await page.getByTestId('rsvp-add-guest').click()
    await page.getByTestId('guest-picker-existing').getByText('Nora').click()

    const [postResponse] = await Promise.all([
      page.waitForResponse(
        (resp) =>
          resp.url().includes(`/api/events/${eventId}/attendances`) &&
          resp.request().method() === 'POST'
      ),
      page.getByTestId('guest-save').click(),
    ])
    expect(postResponse.ok()).toBeTruthy()

    await expect(
      page.getByTestId('attendance-guest-row').filter({ hasText: 'Nora' })
    ).toBeVisible()

    // Same row, back to going — one row per person per event.
    const after = await eventAttendances(eventId)
    const guestRows = after.filter((a) => a.guestId === guestId)
    expect(guestRows.length).toBe(1)
    expect(guestRows[0]!.id).toBe(originalRow.id)
    expect(guestRows[0]!.status).toBe('going')
  })
})
