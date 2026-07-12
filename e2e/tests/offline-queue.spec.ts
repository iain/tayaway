import { test, expect, Page, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getObjectsByType,
  getTestSession,
  getWorkspaceId,
  newApiContext,
  setupAuthenticatedPage,
} from '../helpers'

// The command queue's self-retry exists for fetch failures too brief to drop
// the WebSocket — no reconnect ever fires processQueue, so the queue must
// replay on its own, surface the pending pill meanwhile, and roll the
// optimistic change back (with a toast) if the server permanently rejects it.

// Fail mutation requests at the network level while leaving GETs and the
// auth endpoints (ws-ticket!) alone, so the WebSocket stays authenticated.
async function blockMutations(page: Page): Promise<void> {
  await page.route('**/api/**', (route) => {
    const request = route.request()
    if (request.method() === 'GET' || request.url().includes('/api/auth/')) {
      return route.fallback()
    }
    return route.abort('failed')
  })
}

async function queueTaskListCreate(page: Page, name: string): Promise<void> {
  await page.goto('/tasks')
  await expect(page.getByTestId('page-title')).toContainText('Tasks', {
    timeout: PAGE_LOAD_TIMEOUT,
  })

  await blockMutations(page)

  await page.getByTestId('add-task-list-button').click()
  await page.getByTestId('new-list-name-input').fill(name)
  await page.getByTestId('submit-button').click()

  // The create is queued: optimistic card, offline toast, pending pill.
  await expect(
    page.getByText('Task list will be created when back online')
  ).toBeVisible({ timeout: 10_000 })
  await expect(page.getByText(name)).toBeVisible()
  await expect(page.getByTestId('pending-changes-pill')).toBeVisible({
    timeout: 10_000,
  })
}

test.describe('Offline command queue', () => {
  let apiContext: APIRequestContext

  test.afterEach(async () => {
    await apiContext.dispose()
  })

  test('replays a queued change on its own once the network recovers', async ({
    page,
    playwright,
  }) => {
    apiContext = await newApiContext(playwright)
    const { token } = await getTestSession(
      apiContext,
      'offline-queue-retry@example.com',
      'Queue Retry User'
    )
    await setupAuthenticatedPage(page, token)

    await queueTaskListCreate(page, 'Offline Retry List')

    // Network recovers. Nothing else triggers a replay (the socket never
    // dropped) — the queue's own retry must fire within its backoff window.
    await page.unroute('**/api/**')

    await expect(page.getByTestId('pending-changes-pill')).toBeHidden({
      timeout: 20_000,
    })
    await expect(page.getByText('Offline Retry List')).toBeVisible()

    // The replay reached the server, not just the local pool.
    const workspaceId = await getWorkspaceId(apiContext)
    const response = await apiContext.get(
      `${API_BASE}/api/task-lists?workspace_id=${workspaceId}`
    )
    const lists = getObjectsByType(
      (await response.json()).objects,
      'taskList'
    )
    expect(lists.map((l) => l.name)).toContain('Offline Retry List')
  })

  test('rolls back the optimistic change when the replay is permanently rejected', async ({
    page,
    playwright,
  }) => {
    apiContext = await newApiContext(playwright)
    const { token } = await getTestSession(
      apiContext,
      'offline-queue-rollback@example.com',
      'Queue Rollback User'
    )
    await setupAuthenticatedPage(page, token)

    await queueTaskListCreate(page, 'Doomed List')

    // Swap the network failure for a permanent server rejection before the
    // retry fires.
    await page.unroute('**/api/**')
    await page.route('**/api/task-lists', (route) =>
      route.request().method() === 'GET'
        ? route.fallback()
        : route.fulfill({
            status: 422,
            contentType: 'application/json',
            body: JSON.stringify({ error: 'Validation failed' }),
          })
    )

    // The replay's 422 undoes the optimistic card and says what was lost.
    await expect(
      page.getByText(/offline task list change couldn't be saved/)
    ).toBeVisible({ timeout: 20_000 })
    await expect(page.getByText('Doomed List')).toBeHidden()
    await expect(page.getByTestId('pending-changes-pill')).toBeHidden()

    await page.unroute('**/api/task-lists')
  })
})
