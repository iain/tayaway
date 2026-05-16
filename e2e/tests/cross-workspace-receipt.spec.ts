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

// Pins the cross-workspace receipt invariant: when a per-user event fires in
// workspace B, a session sitting in workspace A must see the consequence
// without reloading or switching. Today this rides the member/notification
// fanout to the user audience; the planned topic/subscription refactor
// must preserve the same observable behaviour.
const RUN_TAG = Date.now().toString(36)
const USER_EMAIL = `e2e-cross-recv-${RUN_TAG}@example.com`
const USER_NAME = 'E2E Cross-Receipt User'
const OWNER_B_EMAIL = `e2e-cross-recv-ownerb-${RUN_TAG}@example.com`
const OWNER_B_NAME = 'E2E Cross-Receipt Owner B'
const A_NAME = `Recv-A-${RUN_TAG}`
const B_NAME = `Recv-B-${RUN_TAG}`

test.describe('Cross-workspace receipt', () => {
  test.describe.configure({ mode: 'serial' })

  let userContext: APIRequestContext
  let ownerBContext: APIRequestContext
  let userToken: string
  let workspaceA: string
  let workspaceB: string
  let userMembershipInB: string

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

    userMembershipInB = await addMemberToWorkspace(
      ownerBContext,
      workspaceB,
      USER_EMAIL
    )
  })

  test.afterAll(async () => {
    await userContext?.dispose()
    await ownerBContext?.dispose()
  })

  test('a member-role change in another workspace badges the workspace selector live', async ({
    page,
  }) => {
    // Sit in workspace A. The selector should already list both A and B
    // because PersonalSync delivered the user's memberships on connect.
    await setupAuthenticatedPage(page, userToken)
    await page.goto('/events')
    await expect(
      page.getByTestId('workspace-switcher-trigger').first()
    ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

    // Confirm the dot is NOT present before the trigger. Open the menu,
    // assert, close it again so it doesn't intercept the next click.
    const trigger = page.getByTestId('workspace-switcher-trigger').first()
    await trigger.click()
    const bOption = page
      .locator(
        `[data-testid="workspace-switcher-option"][data-workspace-id="${workspaceB}"]`
      )
      .first()
    await expect(bOption).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
    await expect(bOption.getByText(/\d+\s+unread/)).toHaveCount(0)
    await page.keyboard.press('Escape')

    // Cross-workspace trigger: owner of B promotes USER to admin. That
    // fires a member_role_changed in-app notification to USER, which the
    // listener delivers on the user-audience channel. The notification
    // carries workspaceId=B, so unreadCountByOtherWorkspace bumps B's
    // bucket and AuthenticatedLayout renders an <UnreadDot> next to B.
    const promote = await ownerBContext.put(
      `${API_BASE}/api/members/${userMembershipInB}`,
      { data: { role: 'admin' } }
    )
    expect(promote.ok()).toBeTruthy()

    // Reopen the selector and wait for the dot. The sr-only text inside
    // <UnreadDot> renders as "<count> unread" — that's our assertion
    // surface (and stays stable under the planned refactor since it's
    // pure UI markup, not transport).
    await trigger.click()
    await expect(bOption.getByText(/\d+\s+unread/)).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
  })
})
