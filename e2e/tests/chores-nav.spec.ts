import { test, expect, APIRequestContext } from '@playwright/test'
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

/** Each test gets its own user: /chores shows every current event in the
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

test.describe('Chores in the main navigation', () => {
  test('nav item opens the roster of the event under way', async ({
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
      `e2e-chores-nav-current-${uid}@example.com`,
      'Chores Nav Current'
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

    await page
      .getByTestId('main-nav')
      .getByRole('link', { name: 'Chores', exact: true })
      .click()

    await expect(page).toHaveURL('/chores')
    await expect(page.getByText(`Alpine Week ${uid}`)).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
    await expect(page.getByText('Cooking')).toBeVisible()
  })

  test('shows a roster for each event under way', async ({
    page,
    playwright,
  }) => {
    const uid = Date.now()
    const { ctx, token } = await freshUser(
      playwright,
      `e2e-chores-nav-overlap-${uid}@example.com`,
      'Chores Nav Overlap'
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

    await expect(page.getByText(`Beach House ${uid}`)).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
    await expect(page.getByText(`City Break ${uid}`)).toBeVisible()
    await expect(page.getByText('Washing up')).toBeVisible()
    await expect(page.getByText('Shopping')).toBeVisible()

    // One roster section per event under way, not a single merged view.
    await expect(page.getByTestId('chore-roster-section')).toHaveCount(2)

    // Exercise a mutation in the SECOND section specifically — the section
    // that's most at risk of popover mis-anchoring or an optimistic update
    // landing in the wrong roster when two sections are mounted side by side.
    const secondSection = page.locator(
      `[data-testid="chore-roster-section"][data-event-id="${secondId}"]`
    )
    const firstSection = page.locator(
      `[data-testid="chore-roster-section"][data-event-id="${firstId}"]`
    )

    await secondSection.getByTitle('Assign someone').first().click()
    await expect(
      secondSection.locator('.fixed.z-50').getByText('Shopping')
    ).toBeVisible()

    const [assignResp] = await Promise.all([
      page.waitForResponse(
        (resp) =>
          resp.url().includes('/assignments') &&
          resp.request().method() === 'POST'
      ),
      secondSection
        .getByRole('button', { name: 'Assign You', exact: true })
        .click(),
    ])
    expect(assignResp.status()).toBe(201)

    // The assignment shows up in the second section's roster...
    await expect(
      secondSection.getByRole('button', { name: /pinned/i }).first()
    ).toBeVisible()
    // ...and does not leak into the first event's roster.
    await expect(
      firstSection.getByRole('button', { name: /pinned/i })
    ).toHaveCount(0)
  })

  test('falls back to the next upcoming event when none is under way', async ({
    page,
    playwright,
  }) => {
    const uid = Date.now()
    const { ctx, token } = await freshUser(
      playwright,
      `e2e-chores-nav-upcoming-${uid}@example.com`,
      'Chores Nav Upcoming'
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

  test('shows the empty state when there is no active event', async ({
    page,
    playwright,
  }) => {
    const uid = Date.now()
    const { ctx, token } = await freshUser(
      playwright,
      `e2e-chores-nav-empty-${uid}@example.com`,
      'Chores Nav Empty'
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
