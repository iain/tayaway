import { test, expect, APIRequestContext, Page } from '@playwright/test'
import {
  API_BASE,
  getObjectByType,
  getTestSession,
  setupAuthenticatedPage,
  createDatedEvent,
  offsetDate,
  newApiContext,
  PAGE_LOAD_TIMEOUT,
} from '../helpers'

/** Each test gets its own user: focus is derived from every event in the
 *  workspace, and the suite runs fullyParallel. */
async function freshUser(
  playwright: { request: { newContext: (options?: object) => Promise<APIRequestContext> } },
  email: string,
  name: string
): Promise<{ ctx: APIRequestContext; token: string }> {
  const ctx = await newApiContext(playwright)
  const { token } = await getTestSession(ctx, email, name)
  return { ctx, token }
}

/** Open the command palette via keyboard and wait for the search input. */
async function openPalette(page: Page): Promise<void> {
  // Click body first: with focus outside the page content the browser may
  // swallow Ctrl+K for its own address bar.
  await page.locator('body').click()
  await page.keyboard.press('Control+k')
  await expect(page.getByPlaceholder('Search...')).toBeVisible()
}

async function seedRoster(
  request: APIRequestContext,
  eventId: string,
  choreName: string
): Promise<void> {
  const rosterResponse = await request.post(`${API_BASE}/api/chore-rosters`, {
    data: { event_id: eventId },
  })
  const rosterBody = await rosterResponse.json()
  const roster = getObjectByType(rosterBody.objects, 'choreRoster')
  await request.post(`${API_BASE}/api/chore-rosters/${roster!.id}/chores`, {
    data: { name: choreName, people_per_day: 1 },
  })
}

test.describe('Current event focus', () => {
  test('names the focused event everywhere, and /chores hands off to it', async ({
    page,
    playwright,
  }) => {
    // Freshly generated per attempt (including CI retries) so a retry never
    // collides with the event/user the first attempt already left behind in
    // the DB: the DB is only reset once per run, so a fixed name would render
    // twice on the retry and break the strict-mode text queries below.
    const uid = Date.now()
    const { ctx, token } = await freshUser(
      playwright,
      `e2e-focus-current-${uid}@example.com`,
      'Focus Current'
    )
    const eventId = await createDatedEvent(
      ctx,
      `Alpine Week ${uid}`,
      offsetDate(-1),
      offsetDate(1)
    )
    await seedRoster(ctx, eventId, 'Cooking')
    await ctx.dispose()

    await setupAuthenticatedPage(page, token)
    await page.goto('/')

    // The bar names the focused event on workspace pages too, not just while
    // you happen to be inside the event.
    await expect(page.getByTestId('event-name')).toHaveText(
      `Alpine Week ${uid}`,
      { timeout: PAGE_LOAD_TIMEOUT }
    )

    // The old standalone chores page is now just a bookmark: it hands off to
    // the focused event's own tab.
    await page.goto('/chores')

    await expect(page).toHaveURL(`/events/${eventId}/chores`)
    await expect(page.getByText('Cooking')).toBeVisible()
  })

  test('shows the focused event only, and follows the switcher', async ({
    page,
    playwright,
  }) => {
    const uid = Date.now()
    const { ctx, token } = await freshUser(
      playwright,
      `e2e-focus-overlap-${uid}@example.com`,
      'Focus Overlap'
    )
    const firstId = await createDatedEvent(
      ctx,
      `Beach House ${uid}`,
      offsetDate(-2),
      offsetDate(2)
    )
    const secondId = await createDatedEvent(
      ctx,
      `City Break ${uid}`,
      offsetDate(-1),
      offsetDate(3)
    )
    await seedRoster(ctx, firstId, 'Washing up')
    await seedRoster(ctx, secondId, 'Shopping')
    await ctx.dispose()

    await setupAuthenticatedPage(page, token)
    await page.goto('/chores')

    // One roster, not a stack of them: focus lands on the event ending
    // soonest, and the subheader says which one you're looking at.
    await expect(page).toHaveURL(`/events/${firstId}/chores`, {
      timeout: PAGE_LOAD_TIMEOUT,
    })
    await expect(page.getByTestId('chore-roster-section')).toHaveCount(1)
    await expect(page.getByText('Washing up')).toBeVisible()
    await expect(page.getByTestId('event-name')).toHaveText(
      `Beach House ${uid}`
    )

    // The switcher is how you reach the overlapping trip — and the page
    // follows focus without going through the events list.
    await page.getByTestId('focus-switcher-trigger').click()
    await page
      .locator(`[data-testid="focus-switcher-option"][data-event-id="${secondId}"]`)
      .click()

    await expect(page).toHaveURL(`/events/${secondId}/chores`)
    await expect(page.getByTestId('event-name')).toHaveText(`City Break ${uid}`)
    await expect(page.getByText('Shopping')).toBeVisible()
    await expect(page.getByTestId('chore-roster-section')).toHaveCount(1)
  })

  test('falls back to the next upcoming event when none is under way', async ({
    page,
    playwright,
  }) => {
    const uid = Date.now()
    const { ctx, token } = await freshUser(
      playwright,
      `e2e-focus-upcoming-${uid}@example.com`,
      'Focus Upcoming'
    )
    const soonId = await createDatedEvent(
      ctx,
      `Next Weekend ${uid}`,
      offsetDate(7),
      offsetDate(9)
    )
    await createDatedEvent(
      ctx,
      `Far Future ${uid}`,
      offsetDate(30),
      offsetDate(32)
    )
    await seedRoster(ctx, soonId, 'Packing')
    await ctx.dispose()

    await setupAuthenticatedPage(page, token)
    await page.goto('/chores')

    await expect(page.getByText(`Next Weekend ${uid}`)).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
    await expect(page.getByText('Packing')).toBeVisible()
    await expect(page.getByText(`Far Future ${uid}`)).toBeHidden()
  })

  // Focus is otherwise inescapable: derivation always picks something, so
  // without an explicit "none" the bar can be pointed elsewhere but never put
  // away. The palette is where that lives, alongside switching workspace.
  test('unfocuses from the command palette, and picks the event back up', async ({
    page,
    playwright,
  }) => {
    const uid = Date.now()
    const { ctx, token } = await freshUser(
      playwright,
      `e2e-focus-unfocus-${uid}@example.com`,
      'Focus Unfocus'
    )
    const eventId = await createDatedEvent(
      ctx,
      `Alpine Week ${uid}`,
      offsetDate(-1),
      offsetDate(1)
    )
    await seedRoster(ctx, eventId, 'Cooking')
    await ctx.dispose()

    await setupAuthenticatedPage(page, token)
    await page.goto('/')

    await expect(page.getByTestId('event-name')).toHaveText(
      `Alpine Week ${uid}`,
      { timeout: PAGE_LOAD_TIMEOUT }
    )

    await openPalette(page)
    await page.getByPlaceholder('Search...').fill('Stop showing')
    await page
      .getByRole('dialog')
      .getByText(`Stop showing Alpine Week ${uid}`)
      .click()

    // Gone from the chrome, and genuinely put away rather than merely hidden:
    // /chores has nothing left to hand off to.
    await expect(page.getByTestId('event-name')).toHaveCount(0)
    await page.goto('/chores')
    await expect(page.getByText('No active event')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // And back again the way the user would put it back: going to the event
    // is what makes the app about it again — there is no separate command.
    await openPalette(page)
    await page.getByPlaceholder('Search...').fill(`Alpine Week ${uid}`)
    await page.getByRole('dialog').getByText(`Alpine Week ${uid}`).click()

    await expect(page).toHaveURL(`/events/${eventId}`)
    await expect(page.getByTestId('event-name')).toHaveText(
      `Alpine Week ${uid}`
    )
  })

  // Inside the event the subheader comes from the URL, so clearing focus on
  // its own would leave the screen unchanged and look like nothing happened.
  test('leaves the event for the events list when told to stop showing it', async ({
    page,
    playwright,
  }) => {
    const uid = Date.now()
    const { ctx, token } = await freshUser(
      playwright,
      `e2e-focus-leave-${uid}@example.com`,
      'Focus Leave'
    )
    const eventId = await createDatedEvent(
      ctx,
      `Ardennes Cabin ${uid}`,
      offsetDate(-1),
      offsetDate(1)
    )
    await ctx.dispose()

    await setupAuthenticatedPage(page, token)
    await page.goto(`/events/${eventId}/expenses`)

    await expect(page.getByTestId('event-name')).toHaveText(
      `Ardennes Cabin ${uid}`,
      { timeout: PAGE_LOAD_TIMEOUT }
    )

    await openPalette(page)
    await page.getByPlaceholder('Search...').fill('Stop showing')
    await page
      .getByRole('dialog')
      .getByText(`Stop showing Ardennes Cabin ${uid}`)
      .click()

    // The events list carries `event-name` on every row, so the subheader's
    // own tabs are what says whether the bar is there.
    await expect(page).toHaveURL('/events')
    await expect(page.getByTestId('event-tabs')).toHaveCount(0)

    // And it stayed put, rather than the bar coming back on the next page.
    await page.goto('/')
    await expect(page.getByTestId('page-title')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
    await expect(page.getByTestId('event-tabs')).toHaveCount(0)
  })

  test('shows the empty state when there is no active event', async ({
    page,
    playwright,
  }) => {
    const uid = Date.now()
    const { ctx, token } = await freshUser(
      playwright,
      `e2e-focus-empty-${uid}@example.com`,
      'Focus Empty'
    )
    await ctx.dispose()

    await setupAuthenticatedPage(page, token)
    await page.goto('/chores')

    await expect(page.getByText('No active event')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
    await expect(
      page.getByText(
        'Chores show up here once an event is under way or coming up.'
      )
    ).toBeVisible()
    await expect(page.getByRole('link', { name: 'View events' })).toBeVisible()
  })
})
