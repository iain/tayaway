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

// Pins the new-workspace bootstrap invariant: a user signed in to only
// workspace A, who gets added to workspace B mid-session, should see B
// appear in the workspace selector without reloading. The Listener
// detects the member change, subscribes the affected user's connections
// to the new workspace topic, and ships a one-shot WorkspaceSync so
// their pool gets the workspace row + initial data before broadcasts
// for that workspace start to arrive.
const RUN_TAG = Date.now().toString(36)
const USER_EMAIL = `e2e-ws-boot-${RUN_TAG}@example.com`
const USER_NAME = 'E2E WS Bootstrap User'
const OWNER_B_EMAIL = `e2e-ws-boot-ownerb-${RUN_TAG}@example.com`
const OWNER_B_NAME = 'E2E WS Bootstrap Owner B'
const A_NAME = `Boot-A-${RUN_TAG}`
const B_NAME = `Boot-B-${RUN_TAG}`

test.describe('New-workspace bootstrap', () => {
  test.describe.configure({ mode: 'serial' })

  let userContext: APIRequestContext
  let ownerBContext: APIRequestContext
  let userToken: string
  let workspaceA: string
  let workspaceB: string

  test.beforeAll(async ({ playwright }) => {
    userContext = await newApiContext(playwright)
    const session = await getTestSession(userContext, USER_EMAIL, USER_NAME)
    userToken = session.token
    workspaceA = await getWorkspaceId(userContext)

    ownerBContext = await newApiContext(playwright)
    await getTestSession(ownerBContext, OWNER_B_EMAIL, OWNER_B_NAME)
    workspaceB = await getWorkspaceId(ownerBContext)

    await userContext.put(`${API_BASE}/api/test/workspace`, {
      data: { workspace_id: workspaceA, name: A_NAME },
    })
    await ownerBContext.put(`${API_BASE}/api/test/workspace`, {
      data: { workspace_id: workspaceB, name: B_NAME },
    })
    // Deliberately do NOT pre-add USER to B; the test is about post-
    // connect bootstrap.
  })

  test.afterAll(async () => {
    await userContext?.dispose()
    await ownerBContext?.dispose()
  })

  test('being added to a new workspace mid-session surfaces it in the selector live', async ({
    page,
  }) => {
    await setupAuthenticatedPage(page, userToken)
    await page.goto('/events')

    // Before: USER is in workspace A only. The header renders the workspace
    // name as a plain link with no chevron — AuthenticatedLayout only mounts
    // the switcher trigger when `otherWorkspaces.length > 0`. So the
    // trigger's absence is the "no other workspaces" signal.
    await expect(page.getByText(A_NAME).first()).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
    await expect(page.getByTestId('workspace-switcher-trigger')).toHaveCount(0)

    // Mid-session bootstrap: owner of B adds USER to B. The membership
    // row broadcasts on the user channel; whatever the routing layer is
    // (current user-audience fanout OR a future topic-subscribe flow),
    // workspace B must end up listable in USER's open tab without a reload.
    await addMemberToWorkspace(ownerBContext, workspaceB, USER_EMAIL)

    // After: the switcher trigger must appear (otherWorkspaces is now
    // non-empty), and B must be one of its options.
    await expect(
      page.getByTestId('workspace-switcher-trigger').first()
    ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
    await page.getByTestId('workspace-switcher-trigger').first().click()
    await expect(
      page
        .locator(
          `[data-testid="workspace-switcher-option"][data-workspace-id="${workspaceB}"]`
        )
        .first()
    ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
  })
})
