import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getTestSession,
  setupAuthenticatedPage,
  createResolvedEvent,
  getObjectsByType,
  getWorkspaceId,
  addMemberToWorkspace,
  PAGE_LOAD_TIMEOUT,
  newApiContext,
  RESOLVED_EVENT_START,
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
    // guest gets an explicit day set. The calendar click is scoped to the
    // guest dialog — the member day picker renders its own calendar.
    await page.getByTestId('rsvp-add-guest').click()
    await page.getByTestId('guest-name-input').fill('Emma')
    await page
      .getByRole('dialog', { name: 'Add a guest' })
      .getByTestId(`calendar-day-${RESOLVED_EVENT_END}`)
      .click()

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

  test("a hosted guest's days shift the settlement onto the host", async ({
    playwright,
  }) => {
    // Alice (creator, auto-RSVPed for the whole 7-day event) brings Emma for
    // the whole event. Bob attends alone and pays €210 for the house.
    // Head-days: Alice 7 + Emma 7 (billed to Alice) = 14, Bob 7, total 21 —
    // Alice's share is 14/21·210 = €140, not the €105 a guest-blind split
    // would give. This restores the coverage the plus-ones stepper e2e
    // carried before named guests replaced it.
    const { eventId } = await createResolvedEvent(apiContext, 'Guest settle')
    const meResp = await apiContext.get(`${API_BASE}/api/auth/me`)
    const aliceId = (await meResp.json()).user_id as string

    await apiContext.post(`${API_BASE}/api/events/${eventId}/attendances`, {
      data: {
        id: crypto.randomUUID(),
        status: 'going',
        guest: { id: crypto.randomUUID(), name: 'Settle Emma' },
      },
    })

    const bobEmail = 'e2e-guests-settle-bob@example.com'
    const bobContext = await newApiContext(playwright)
    const { userId: bobId } = await getTestSession(
      bobContext,
      bobEmail,
      'Guest Settle Bob'
    )
    const workspaceId = await getWorkspaceId(apiContext)
    await addMemberToWorkspace(apiContext, workspaceId, bobEmail)
    await bobContext.post(`${API_BASE}/api/events/${eventId}/attendances`, {
      data: { id: crypto.randomUUID(), status: 'going' },
    })
    const expenseResp = await bobContext.post(`${API_BASE}/api/expenses`, {
      data: {
        event_id: eventId,
        description: 'Group house',
        amount: 210,
        start_date: RESOLVED_EVENT_START,
        end_date: RESOLVED_EVENT_END,
      },
    })
    expect(expenseResp.status()).toBe(201)
    await bobContext.dispose()

    const settleResp = await apiContext.post(`${API_BASE}/api/settlements`, {
      data: { event_id: eventId },
    })
    expect(settleResp.status()).toBe(201)
    const transfers = getObjectsByType(
      (await settleResp.json()).objects,
      'settlementTransfer'
    ) as Array<{ fromUserId: string; toUserId: string; amount: number }>
    expect(transfers.length).toBe(1)
    expect(transfers[0]!.fromUserId).toBe(aliceId)
    expect(transfers[0]!.toUserId).toBe(bobId)
    expect(transfers[0]!.amount).toBeCloseTo(140, 2)
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
