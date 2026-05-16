import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getTestSession,
  setupAuthenticatedPage,
  getWorkspaceId,
  addMemberToWorkspace,
  newApiContext,
} from '../helpers'

// Unique per run so we don't fight stale rows from earlier test runs.
const RUN_TAG = Date.now().toString(36)
const USER_EMAIL = `e2e-ws-switch-${RUN_TAG}@example.com`
const USER_NAME = 'E2E WS Switch Primary'
const OTHER_OWNER_EMAIL = `e2e-ws-switch-other-${RUN_TAG}@example.com`
const OTHER_OWNER_NAME = 'E2E WS Switch Other Owner'
const ALPHA_NAME = `Alpha-${RUN_TAG}`
const BETA_NAME = `Beta-${RUN_TAG}`
const EVENT_ALPHA = `Event-Alpha-${RUN_TAG}`
const EVENT_BETA = `Event-Beta-${RUN_TAG}`

// Captures the integration-level workspace-switch bug that the unit tests
// can't reach: clicking a workspace in the selector should fire a
// `switch_workspace` WS frame and surface the new workspace's data
// without a reload. The regression let the click silently no-op.
test.describe('Workspace switching', () => {
  test.describe.configure({ mode: 'serial' })

  let primaryContext: APIRequestContext
  let otherOwnerContext: APIRequestContext
  let sessionToken: string
  let workspaceA: string
  let workspaceB: string

  test.beforeAll(async ({ playwright }) => {
    primaryContext = await newApiContext(playwright)
    const session = await getTestSession(primaryContext, USER_EMAIL, USER_NAME)
    sessionToken = session.token
    workspaceA = await getWorkspaceId(primaryContext)

    otherOwnerContext = await newApiContext(playwright)
    await getTestSession(otherOwnerContext, OTHER_OWNER_EMAIL, OTHER_OWNER_NAME)
    workspaceB = await getWorkspaceId(otherOwnerContext)

    await primaryContext.put(`${API_BASE}/api/test/workspace`, {
      data: { workspace_id: workspaceA, name: ALPHA_NAME },
    })
    await otherOwnerContext.put(`${API_BASE}/api/test/workspace`, {
      data: { workspace_id: workspaceB, name: BETA_NAME },
    })

    await addMemberToWorkspace(otherOwnerContext, workspaceB, USER_EMAIL)

    await primaryContext.post(`${API_BASE}/api/events`, {
      data: { name: EVENT_ALPHA, description: 'only in Alpha' },
    })
    await otherOwnerContext.post(`${API_BASE}/api/events`, {
      data: { name: EVENT_BETA, description: 'only in Beta' },
    })
  })

  test.afterAll(async () => {
    await primaryContext?.dispose()
    await otherOwnerContext?.dispose()
  })

  test('switching back to a previously-active workspace brings its data back without a reload', async ({
    page,
  }) => {
    // First switch (A → B) works; the bug is in the switch-back (B → A).
    // Cached data for A is in IndexedDB from the initial sync, but after
    // clearing workspace:A on the way out and the partial sync on the way
    // back, A's data ends up missing from the visible view.
    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/events')
    await expect(page.getByText(EVENT_ALPHA)).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // A → B
    await page.getByTestId('workspace-switcher-trigger').first().click()
    await page
      .locator(`[data-testid="workspace-switcher-option"][data-workspace-id="${workspaceB}"]`)
      .first()
      .click()
    await expect(page.getByText(EVENT_BETA)).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // B → A (the regression: A's data should reappear)
    await page.getByTestId('workspace-switcher-trigger').first().click()
    await page
      .locator(`[data-testid="workspace-switcher-option"][data-workspace-id="${workspaceA}"]`)
      .first()
      .click()
    await expect(page.getByText(EVENT_ALPHA)).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
    await expect(page.getByText(EVENT_BETA)).toBeHidden()
  })

  test('clicking a workspace in the selector swaps the active workspace and its data without a reload', async ({
    page,
  }) => {
    await setupAuthenticatedPage(page, sessionToken)

    // Capture outgoing WebSocket frames so we can prove a switch_workspace
    // message actually went out — the user's report was "no network
    // requests," which this surfaces directly.
    const sentFrames: string[] = []
    page.on('websocket', (ws) => {
      ws.on('framesent', (payload) => {
        if (typeof payload.payload === 'string') {
          sentFrames.push(payload.payload)
        }
      })
    })

    await page.goto('/events')
    await expect(page.getByText(EVENT_ALPHA)).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Open the workspace selector via its test-id (the trigger is a
    // chevron-only button with no visible text).
    await page
      .getByTestId('workspace-switcher-trigger')
      .first()
      .click()
    await page
      .locator(`[data-testid="workspace-switcher-option"][data-workspace-id="${workspaceB}"]`)
      .first()
      .click()

    // After the switch, Event-Beta should appear and Event-Alpha should
    // disappear. If the switch went silent, both assertions time out —
    // which is exactly the bug we're catching.
    await expect(page.getByText(EVENT_BETA)).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
    await expect(page.getByText(EVENT_ALPHA)).toBeHidden()

    // Belt-and-braces: the WS frame for the switch was actually sent.
    const switchFrame = sentFrames.find((f) =>
      f.includes('"type":"switch_workspace"')
    )
    expect(
      switchFrame,
      'expected a switch_workspace WS frame to be sent'
    ).toBeTruthy()
  })
})
