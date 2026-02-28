import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getObjectByType,
  getObjectsByType,
  getTestSession,
  setupAuthenticatedPage,
  createResolvedEvent,
  PAGE_LOAD_TIMEOUT,
} from '../helpers'

const TEST_EMAIL = 'e2e-chores@example.com'
const TEST_NAME = 'E2E Chores User'

// Resolved events use date range 2026-06-01 to 2026-06-07
const DEFAULT_START = '2026-06-01'

/**
 * Creates a chore roster for the given event and returns the roster ID.
 */
async function createRoster(
  request: APIRequestContext,
  eventId: string
): Promise<string> {
  const response = await request.post(`${API_BASE}/api/chore-rosters`, {
    data: { event_id: eventId },
  })
  expect(response.status()).toBe(201)
  const body = await response.json()
  const roster = getObjectByType(body.objects, 'choreRoster')
  return roster!.id
}

/**
 * Adds a chore to a roster and returns the chore ID.
 */
async function addChore(
  request: APIRequestContext,
  rosterId: string,
  name: string,
  peoplePerDay = 1
): Promise<string> {
  const response = await request.post(
    `${API_BASE}/api/chore-rosters/${rosterId}/chores`,
    { data: { name, people_per_day: peoplePerDay } }
  )
  expect(response.status()).toBe(201)
  const body = await response.json()
  const chore = getObjectByType(body.objects, 'chore')
  return chore!.id
}

test.describe('Chore Rosters Feature', () => {
  test.describe('Chore Rosters API - Unauthenticated', () => {
    test('all chore roster endpoints require auth', async ({ request }) => {
      const fakeId = '00000000-0000-0000-0000-000000000000'
      const responses = await Promise.all([
        request.post(`${API_BASE}/api/chore-rosters`, {
          data: { event_id: fakeId },
        }),
        request.get(`${API_BASE}/api/chore-rosters/${fakeId}`),
        request.post(`${API_BASE}/api/chore-rosters/${fakeId}/chores`, {
          data: { name: 'Cooking' },
        }),
        request.post(`${API_BASE}/api/chore-rosters/${fakeId}/autofill`),
      ])
      for (const response of responses) {
        expect(response.status()).toBe(401)
        const body = await response.json()
        expect(body.error).toBe('Authorization required')
      }
    })
  })

  test.describe('Chore Rosters API - Authenticated', () => {
    let apiContext: APIRequestContext
    let userId: string

    test.beforeAll(async ({ playwright }) => {
      apiContext = await playwright.request.newContext()
      const session = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      userId = session.userId
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('full chore roster lifecycle', async () => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Chore Lifecycle Event'
      )

      // Create roster
      const createResp = await apiContext.post(
        `${API_BASE}/api/chore-rosters`,
        { data: { event_id: eventId } }
      )
      expect(createResp.status()).toBe(201)
      const createBody = await createResp.json()
      const roster = getObjectByType(createBody.objects, 'choreRoster')
      expect(roster).toHaveProperty('id')
      expect(roster).toHaveProperty('eventId', eventId)
      const rosterId = roster!.id

      // Get roster
      const getResp = await apiContext.get(
        `${API_BASE}/api/chore-rosters/${rosterId}`
      )
      expect(getResp.ok()).toBeTruthy()
      const getBody = await getResp.json()
      const fetched = getObjectByType(getBody.objects, 'choreRoster')
      expect(fetched?.id).toBe(rosterId)

      // Add chore
      const addChoreResp = await apiContext.post(
        `${API_BASE}/api/chore-rosters/${rosterId}/chores`,
        { data: { name: 'Cooking', people_per_day: 2 } }
      )
      expect(addChoreResp.status()).toBe(201)
      const addChoreBody = await addChoreResp.json()
      const chore = getObjectByType(addChoreBody.objects, 'chore')
      expect(chore?.name).toBe('Cooking')
      expect(chore?.peoplePerDay).toBe(2)
      const choreId = chore!.id

      // Update chore
      const updateChoreResp = await apiContext.put(
        `${API_BASE}/api/chore-rosters/${rosterId}/chores/${choreId}`,
        { data: { name: 'Washing up', people_per_day: 1 } }
      )
      expect(updateChoreResp.ok()).toBeTruthy()
      const updateChoreBody = await updateChoreResp.json()
      const updatedChore = getObjectByType(updateChoreBody.objects, 'chore')
      expect(updatedChore?.name).toBe('Washing up')
      expect(updatedChore?.peoplePerDay).toBe(1)

      // Create assignment (pinned)
      const assignResp = await apiContext.post(
        `${API_BASE}/api/chore-rosters/${rosterId}/assignments`,
        {
          data: {
            chore_id: choreId,
            user_id: userId,
            date: DEFAULT_START,
            note: 'Pizza night',
          },
        }
      )
      expect(assignResp.status()).toBe(201)
      const assignBody = await assignResp.json()
      const assignment = getObjectByType(assignBody.objects, 'choreAssignment')
      expect(assignment?.pinned).toBe(true)
      expect(assignment?.note).toBe('Pizza night')
      const assignmentId = assignment!.id

      // Update assignment
      const updateAssignResp = await apiContext.put(
        `${API_BASE}/api/chore-rosters/${rosterId}/assignments/${assignmentId}`,
        { data: { note: 'Pasta night' } }
      )
      expect(updateAssignResp.ok()).toBeTruthy()
      const updateAssignBody = await updateAssignResp.json()
      const updatedAssign = getObjectByType(
        updateAssignBody.objects,
        'choreAssignment'
      )
      expect(updatedAssign?.note).toBe('Pasta night')

      // Delete assignment
      const deleteAssignResp = await apiContext.delete(
        `${API_BASE}/api/chore-rosters/${rosterId}/assignments/${assignmentId}`
      )
      expect(deleteAssignResp.ok()).toBeTruthy()
      const deleteAssignBody = await deleteAssignResp.json()
      expect(deleteAssignBody.deleted).toHaveLength(1)
      expect(deleteAssignBody.deleted[0].objectType).toBe('choreAssignment')

      // Delete chore
      const deleteChoreResp = await apiContext.delete(
        `${API_BASE}/api/chore-rosters/${rosterId}/chores/${choreId}`
      )
      expect(deleteChoreResp.ok()).toBeTruthy()
      const deleteChoreBody = await deleteChoreResp.json()
      const deletedTypes = deleteChoreBody.deleted.map(
        (d: { objectType: string }) => d.objectType
      )
      expect(deletedTypes).toContain('chore')
    })

    test('duplicate roster creation is rejected', async () => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Duplicate Roster Event'
      )

      const first = await apiContext.post(`${API_BASE}/api/chore-rosters`, {
        data: { event_id: eventId },
      })
      expect(first.status()).toBe(201)

      const second = await apiContext.post(`${API_BASE}/api/chore-rosters`, {
        data: { event_id: eventId },
      })
      expect(second.status()).toBe(400)
      const body = await second.json()
      expect(body.error).toContain('already exists')
    })

    test('autofill creates assignments for all chore-day slots', async () => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Autofill Event'
      )
      const rosterId = await createRoster(apiContext, eventId)
      await addChore(apiContext, rosterId, 'Cooking')

      const autofillResp = await apiContext.post(
        `${API_BASE}/api/chore-rosters/${rosterId}/autofill`
      )
      expect(autofillResp.ok()).toBeTruthy()
      const autofillBody = await autofillResp.json()
      const assignments = getObjectsByType(
        autofillBody.objects,
        'choreAssignment'
      )

      // Event has 7 days, 1 person/day, 1 attendee → 7 assignments
      expect(assignments.length).toBe(7)
      expect(assignments.every((a) => a.pinned === false)).toBeTruthy()
    })

    test('autofill preserves pinned assignments', async () => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Pinned Preserve Event'
      )
      const rosterId = await createRoster(apiContext, eventId)
      const choreId = await addChore(apiContext, rosterId, 'Cooking')

      // Pin an assignment
      const pinResp = await apiContext.post(
        `${API_BASE}/api/chore-rosters/${rosterId}/assignments`,
        {
          data: {
            chore_id: choreId,
            user_id: userId,
            date: DEFAULT_START,
            note: 'Special meal',
          },
        }
      )
      expect(pinResp.status()).toBe(201)

      // Autofill
      const autofillResp = await apiContext.post(
        `${API_BASE}/api/chore-rosters/${rosterId}/autofill`
      )
      expect(autofillResp.ok()).toBeTruthy()
      const body = await autofillResp.json()
      const assignments = getObjectsByType(body.objects, 'choreAssignment')

      // Should have 7 total (1 pinned + 6 auto)
      expect(assignments.length).toBe(7)

      const pinned = assignments.filter((a) => a.pinned === true)
      expect(pinned.length).toBe(1)
      expect(pinned[0]?.note).toBe('Special meal')
      expect(pinned[0]?.date).toBe(DEFAULT_START)
    })

    test('chore validation rejects empty name', async () => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Validation Event'
      )
      const rosterId = await createRoster(apiContext, eventId)

      const resp = await apiContext.post(
        `${API_BASE}/api/chore-rosters/${rosterId}/chores`,
        { data: { name: '', people_per_day: 1 } }
      )
      expect(resp.status()).toBe(400)
    })

    test('assignment date must be within event range', async () => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Date Range Event'
      )
      const rosterId = await createRoster(apiContext, eventId)
      const choreId = await addChore(apiContext, rosterId, 'Cooking')

      const resp = await apiContext.post(
        `${API_BASE}/api/chore-rosters/${rosterId}/assignments`,
        {
          data: {
            chore_id: choreId,
            user_id: userId,
            date: '2026-12-25', // way outside event range
          },
        }
      )
      expect(resp.status()).toBe(400)
    })

    test('delete roster removes roster and all chores/assignments', async () => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Delete Roster Event'
      )
      const rosterId = await createRoster(apiContext, eventId)
      const choreId = await addChore(apiContext, rosterId, 'Cooking')
      await apiContext.post(
        `${API_BASE}/api/chore-rosters/${rosterId}/assignments`,
        {
          data: {
            chore_id: choreId,
            user_id: userId,
            date: DEFAULT_START,
          },
        }
      )

      const deleteResp = await apiContext.delete(
        `${API_BASE}/api/chore-rosters/${rosterId}`
      )
      expect(deleteResp.ok()).toBeTruthy()
      const body = await deleteResp.json()
      const deletedTypes = body.deleted.map(
        (d: { objectType: string }) => d.objectType
      )
      expect(deletedTypes).toContain('choreRoster')
      expect(deletedTypes).toContain('chore')
      expect(deletedTypes).toContain('choreAssignment')

      // Roster should be gone
      const getResp = await apiContext.get(
        `${API_BASE}/api/chore-rosters/${rosterId}`
      )
      expect(getResp.status()).toBe(410)
    })

    test('delete roster rejects non-creator', async ({ playwright }) => {
      const otherCtx = await playwright.request.newContext()
      const otherSession = await getTestSession(
        otherCtx,
        'e2e-chores-other@example.com',
        'Other Chores User'
      )

      // Create event and roster as the original user
      const { eventId } = await createResolvedEvent(
        apiContext,
        'Delete Roster Auth Event'
      )
      const rosterId = await createRoster(apiContext, eventId)

      // Try to delete as other user (who is in the same workspace via test setup)
      const deleteResp = await otherCtx.delete(
        `${API_BASE}/api/chore-rosters/${rosterId}`
      )
      expect(deleteResp.status()).toBe(403)

      await otherCtx.dispose()
    })
  })

  test.describe('Chore Rosters UI', () => {
    let sessionToken: string
    let apiContext: APIRequestContext
    let userId: string
    const uid = Date.now()

    test.beforeAll(async ({ playwright }) => {
      apiContext = await playwright.request.newContext()
      const session = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      sessionToken = session.token
      userId = session.userId
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('chores page redirects to login when not authenticated', async ({
      page,
    }) => {
      const fakeId = '00000000-0000-0000-0000-000000000000'
      await page.goto(`/events/${fakeId}/chores`)
      await expect(page).toHaveURL('/login')
    })

    test('chores page is reachable from event page', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Nav Test Event ${uid}`
      )
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/expenses`)

      await expect(
        page.getByRole('link', { name: 'Chores', exact: true })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
      await page.getByRole('link', { name: 'Chores', exact: true }).click()

      await expect(page).toHaveURL(`/events/${eventId}/chores`)
    })

    test('shows empty state and create roster button', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Empty Roster ${uid}`
      )
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/chores`)

      await expect(page.getByText(/no chore roster/i)).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(
        page.getByRole('button', { name: 'Create roster' })
      ).toBeVisible()
    })

    test('can create a roster and see empty chores state', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Create Roster ${uid}`
      )
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/chores`)

      await expect(
        page.getByRole('button', { name: 'Create roster' })
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      const [createResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/chore-rosters') &&
            resp.request().method() === 'POST'
        ),
        page.getByRole('button', { name: 'Create roster' }).click(),
      ])
      expect(createResp.status()).toBe(201)

      // Should now see the empty chores state with heading and an "Add chore" button
      await expect(page.getByText(/no chores yet/i)).toBeVisible()
    })

    test('can add a chore via the modal', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Add Chore Modal ${uid}`
      )
      await createRoster(apiContext, eventId)

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/chores`)

      // Click "Add chore" button (use first to avoid strict mode with toolbar + empty state)
      await expect(
        page.getByRole('button', { name: 'Add chore' }).first()
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
      await page.getByRole('button', { name: 'Add chore' }).first().click()

      // Modal should open
      await expect(
        page.getByRole('heading', { name: 'Add Chore' })
      ).toBeVisible()

      // Fill in name
      await page.getByLabel('Name').fill('Cooking')
      await page.getByLabel('People per day').fill('2')

      // Submit via the form submit button
      const [addResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/chores') && resp.request().method() === 'POST'
        ),
        page.getByTestId('submit-button').click(),
      ])
      expect(addResp.status()).toBe(201)

      // Chore should appear in the grid
      await expect(page.getByText('Cooking')).toBeVisible()
      await expect(page.getByText('2/day')).toBeVisible()
    })

    test('can run autofill and see assignments in grid', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Autofill UI ${uid}`
      )
      const rosterId = await createRoster(apiContext, eventId)
      await addChore(apiContext, rosterId, 'Cooking')

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/chores`)

      // Wait for chore to be visible in grid
      await expect(page.getByText('Cooking')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Click Auto-fill — now requires confirmation
      await page.getByRole('button', { name: 'Auto-fill' }).click()
      const [autofillResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/autofill') &&
            resp.request().method() === 'POST'
        ),
        page
          .locator('dialog')
          .getByRole('button', { name: 'Auto-fill' })
          .click(),
      ])
      expect(autofillResp.ok()).toBeTruthy()

      // Assignments should appear — the current user's name should show in cells
      await expect(page.getByText(TEST_NAME).first()).toBeVisible()
    })

    test('can pin an assignment via the assign popover', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Pin Assignment ${uid}`
      )
      const rosterId = await createRoster(apiContext, eventId)
      await addChore(apiContext, rosterId, 'Cleaning')

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/chores`)

      // Wait for grid
      await expect(page.getByText('Cleaning')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Click a "+" button on the first empty slot
      await page.getByTitle('Assign member').first().click()

      // Popover should appear with "Assign member" label
      await expect(page.locator('text=Assign member').last()).toBeVisible()

      // Add a note
      await page.getByPlaceholder('Note (optional)').fill('Deep clean')

      // Click the user's name to assign
      const [assignResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/assignments') &&
            resp.request().method() === 'POST'
        ),
        page.getByRole('button', { name: TEST_NAME }).click(),
      ])
      expect(assignResp.status()).toBe(201)

      // Assignment should appear in the grid with the note in the title
      await expect(page.locator('[title*="Deep clean"]').first()).toBeVisible()
    })

    test('delete chore shows confirmation and removes from grid', async ({
      page,
    }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Delete Chore UI ${uid}`
      )
      const rosterId = await createRoster(apiContext, eventId)
      await addChore(apiContext, rosterId, 'Dishes')
      await addChore(apiContext, rosterId, 'Mopping')

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/chores`)

      await expect(page.getByText('Dishes')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(page.getByText('Mopping')).toBeVisible()

      // Click delete button for "Dishes" (force-click since hover-reveal)
      const dishesHeader = page.locator('th').filter({ hasText: 'Dishes' })
      const deleteBtn = dishesHeader.getByRole('button', {
        name: 'Delete chore',
      })
      await deleteBtn.click({ force: true })

      // Confirmation dialog should appear
      await expect(
        page.getByText('Delete "Dishes"?', { exact: false })
      ).toBeVisible()

      // Confirm deletion
      const [deleteResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/chore-rosters/') &&
            resp.url().includes('/chores/') &&
            resp.request().method() === 'DELETE'
        ),
        page.locator('dialog').getByRole('button', { name: 'Delete' }).click(),
      ])
      expect(deleteResp.ok()).toBeTruthy()

      // "Dishes" should be gone, "Mopping" should remain
      await expect(page.getByText('Dishes')).not.toBeVisible()
      await expect(page.getByText('Mopping')).toBeVisible()
    })

    test('autofill shows confirmation dialog', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Autofill Confirm ${uid}`
      )
      const rosterId = await createRoster(apiContext, eventId)
      await addChore(apiContext, rosterId, 'Cooking')

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/chores`)

      await expect(page.getByText('Cooking')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Click Auto-fill — should show confirmation
      await page.getByRole('button', { name: 'Auto-fill' }).click()
      await expect(
        page.getByText('replace all non-pinned assignments', { exact: false })
      ).toBeVisible()

      // Confirm autofill
      const [autofillResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/autofill') &&
            resp.request().method() === 'POST'
        ),
        page
          .locator('dialog')
          .getByRole('button', { name: 'Auto-fill' })
          .click(),
      ])
      expect(autofillResp.ok()).toBeTruthy()

      // Assignments should appear
      await expect(page.getByText(TEST_NAME).first()).toBeVisible()
    })

    test('can edit assignment note via popover', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Edit Assignment ${uid}`
      )
      const rosterId = await createRoster(apiContext, eventId)
      await addChore(apiContext, rosterId, 'Cleaning')

      // Pin an assignment via API
      const choreResp = await apiContext.get(
        `${API_BASE}/api/chore-rosters/${rosterId}`
      )
      const choreBody = await choreResp.json()
      const chore = getObjectByType(choreBody.objects, 'chore')

      await apiContext.post(
        `${API_BASE}/api/chore-rosters/${rosterId}/assignments`,
        {
          data: {
            chore_id: chore!.id,
            user_id: userId,
            date: DEFAULT_START,
            note: 'Original note',
          },
        }
      )

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/chores`)

      // Wait for assignment to be visible
      await expect(
        page.locator('[title*="Original note"]').first()
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Click the assignment chip to open edit popover
      await page.locator('[title*="Original note"]').first().click()

      // Popover should show member name
      await expect(
        page.locator('.fixed.z-50').getByText(TEST_NAME)
      ).toBeVisible()

      // Update the note
      const noteInput = page
        .locator('.fixed.z-50')
        .getByPlaceholder('Note (optional)')
      await noteInput.clear()
      await noteInput.fill('Updated note')

      // Click Save
      const [updateResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/assignments/') &&
            resp.request().method() === 'PUT'
        ),
        page
          .locator('.fixed.z-50')
          .getByRole('button', { name: 'Save' })
          .click(),
      ])
      expect(updateResp.ok()).toBeTruthy()

      // Updated note should be in the title
      await expect(
        page.locator('[title*="Updated note"]').first()
      ).toBeVisible()
    })

    test('can remove assignment via popover', async ({ page }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Remove Assignment ${uid}`
      )
      const rosterId = await createRoster(apiContext, eventId)
      await addChore(apiContext, rosterId, 'Sweeping')

      // Pin an assignment via API
      const choreResp = await apiContext.get(
        `${API_BASE}/api/chore-rosters/${rosterId}`
      )
      const choreBody = await choreResp.json()
      const chore = getObjectByType(choreBody.objects, 'chore')

      await apiContext.post(
        `${API_BASE}/api/chore-rosters/${rosterId}/assignments`,
        {
          data: {
            chore_id: chore!.id,
            user_id: userId,
            date: DEFAULT_START,
          },
        }
      )

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/chores`)

      // Wait for assignment chip to be visible
      await expect(
        page.locator('button').filter({ hasText: TEST_NAME }).first()
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Click the assignment chip
      await page
        .locator('button')
        .filter({ hasText: TEST_NAME })
        .first()
        .click()

      // Click Remove in the popover
      const [deleteResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/assignments/') &&
            resp.request().method() === 'DELETE'
        ),
        page
          .locator('.fixed.z-50')
          .getByRole('button', { name: 'Remove' })
          .click(),
      ])
      expect(deleteResp.ok()).toBeTruthy()
    })

    test('delete roster removes it and shows create button', async ({
      page,
    }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Delete Roster ${uid}`
      )
      await createRoster(apiContext, eventId)

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/chores`)

      // Wait for roster to load (toolbar visible)
      await expect(
        page.getByRole('button', { name: 'Add chore' }).first()
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Click delete roster button
      await page.getByRole('button', { name: 'Delete roster' }).click()

      // Confirmation dialog should appear
      await expect(
        page.getByText('All chores and assignments will be removed', {
          exact: false,
        })
      ).toBeVisible()

      // Confirm deletion
      const [deleteResp] = await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/chore-rosters/') &&
            resp.request().method() === 'DELETE' &&
            !resp.url().includes('/chores/') &&
            !resp.url().includes('/assignments/')
        ),
        page.locator('dialog').getByRole('button', { name: 'Delete' }).click(),
      ])
      expect(deleteResp.ok()).toBeTruthy()

      // Should show create roster button again
      await expect(
        page.getByRole('button', { name: 'Create roster' })
      ).toBeVisible()
    })

    test('workload table column order updates after chore reorder', async ({
      page,
    }) => {
      const { eventId } = await createResolvedEvent(
        apiContext,
        `Workload Reorder ${uid}`
      )
      const rosterId = await createRoster(apiContext, eventId)
      await addChore(apiContext, rosterId, 'Cooking')
      await addChore(apiContext, rosterId, 'Cleaning')

      // Autofill so the workload table appears
      await apiContext.post(
        `${API_BASE}/api/chore-rosters/${rosterId}/autofill`
      )

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto(`/events/${eventId}/chores`)

      // Wait for workload table to appear
      await expect(page.getByRole('heading', { name: 'Workload' })).toBeVisible(
        { timeout: PAGE_LOAD_TIMEOUT }
      )

      const workloadHeaders = page
        .locator('h2', { hasText: 'Workload' })
        .locator('..')
        .locator('thead th')
      const gridHeaders = page.locator('.chore-col')

      // Initial order: Cooking, Cleaning
      await expect(workloadHeaders.nth(1)).toHaveText('Cooking')
      await expect(workloadHeaders.nth(2)).toHaveText('Cleaning')

      // Helper: drag one chore handle to another's position
      async function dragChore(fromIndex: number, toIndex: number) {
        const handles = page.locator('.chore-drag-handle')
        const source = handles.nth(fromIndex)
        // Hover first so the handle is interactable
        await source.hover()
        const sourceBox = await source.boundingBox()
        const targetBox = await handles.nth(toIndex).boundingBox()
        expect(sourceBox).not.toBeNull()
        expect(targetBox).not.toBeNull()

        const responsePromise = page.waitForResponse(
          (resp) =>
            resp.url().includes('/chore-rosters/') &&
            resp.url().includes('/chores/') &&
            resp.request().method() === 'PUT'
        )

        await page.mouse.move(
          sourceBox!.x + sourceBox!.width / 2,
          sourceBox!.y + sourceBox!.height / 2
        )
        await page.mouse.down()
        await page.waitForTimeout(100) // Let SortableJS recognize the drag
        // Move past the target edge to trigger SortableJS swap
        const targetX =
          fromIndex < toIndex
            ? targetBox!.x + targetBox!.width - 5
            : targetBox!.x + 5
        await page.mouse.move(targetX, targetBox!.y + targetBox!.height / 2, {
          steps: 15,
        })
        await page.mouse.up()

        const resp = await responsePromise
        expect(resp.ok()).toBeTruthy()
      }

      // Drag Cooking (0) right to after Cleaning (1)
      await dragChore(0, 1)

      await expect(gridHeaders.nth(0)).toContainText('Cleaning')
      await expect(gridHeaders.nth(1)).toContainText('Cooking')
      await expect(workloadHeaders.nth(1)).toHaveText('Cleaning')
      await expect(workloadHeaders.nth(2)).toHaveText('Cooking')

      // Wait for reactive updates and SortableJS animation to settle
      await page.waitForTimeout(500)

      // Drag Cooking (now at 1) back left to before Cleaning (now at 0)
      await dragChore(1, 0)

      await expect(gridHeaders.nth(0)).toContainText('Cooking')
      await expect(gridHeaders.nth(1)).toContainText('Cleaning')
      await expect(workloadHeaders.nth(1)).toHaveText('Cooking')
      await expect(workloadHeaders.nth(2)).toHaveText('Cleaning')
    })

    test('shows RSVP required dialog for non-attending user', async ({
      page,
      playwright,
    }) => {
      const ctx = await playwright.request.newContext()
      const { token } = await getTestSession(
        ctx,
        'e2e-chores-rsvp@example.com',
        'Chores RSVP User'
      )
      // createResolvedEvent auto-RSVPs the user as attending; change to not attending
      const { eventId } = await createResolvedEvent(ctx, 'Chores RSVP Test')
      const rosterId = await createRoster(ctx, eventId)
      await addChore(ctx, rosterId, 'Cooking')

      await ctx.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
        data: { attending: false },
      })
      await ctx.dispose()

      await setupAuthenticatedPage(page, token)
      await page.goto(`/events/${eventId}/chores`)

      await expect(page.getByText('Cooking')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Click "Add chore" in the toolbar
      await page.getByRole('button', { name: 'Add chore' }).click()

      // RSVP dialog should appear
      await expect(page.getByText('RSVP required')).toBeVisible()
      await expect(page.getByRole('link', { name: 'Go to RSVP' })).toBeVisible()

      // Link should navigate to RSVP page
      await page.getByRole('link', { name: 'Go to RSVP' }).click()
      await expect(page).toHaveURL(`/events/${eventId}/rsvp`)
    })
  })
})
