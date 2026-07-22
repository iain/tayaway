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

// The outside-in driver for workspace management (see CLAUDE.md: this test
// stays red while the backend services and the UI come up under it).
//
// Contract it pins down:
//   - Settings' sidebar is grouped: one "Personal" group, then one group per
//     workspace the user administers. Groups for *every* such workspace are
//     listed regardless of which workspace is currently active — settings is
//     the cross-workspace surface.
//   - You can create a workspace from there, and creating one drops you into
//     it.
//   - Name and timezone are editable, and the edits survive switching away
//     and back with no reload (they ride the pool, not a page fetch).
const RUN_TAG = Date.now().toString(36)
const USER_EMAIL = `e2e-ws-settings-${RUN_TAG}@example.com`
const USER_NAME = 'E2E WS Settings User'
const ALPHA_NAME = `Alpha-${RUN_TAG}`
const BETA_NAME = `Beta-${RUN_TAG}`
const BETA_RENAMED = `Beta-Renamed-${RUN_TAG}`

const OTHER_OWNER_EMAIL = `e2e-ws-settings-other-${RUN_TAG}@example.com`
const OTHER_OWNER_NAME = 'E2E WS Settings Other Owner'
const GAMMA_NAME = `Gamma-${RUN_TAG}`

function settingsGroup(page: import('@playwright/test').Page, id: string) {
  return page.locator(
    `[data-testid="settings-nav-group"][data-workspace-id="${id}"]`
  )
}

async function switchToWorkspace(
  page: import('@playwright/test').Page,
  id: string
) {
  await page.getByTestId('workspace-switcher-trigger').first().click()
  await page
    .locator(`[data-testid="workspace-switcher-option"][data-workspace-id="${id}"]`)
    .first()
    .click()
}

test.describe('Workspace settings', () => {
  test.describe.configure({ mode: 'serial' })

  let apiContext: APIRequestContext
  let sessionToken: string
  let workspaceAlpha: string

  test.beforeAll(async ({ playwright }) => {
    apiContext = await newApiContext(playwright)
    const session = await getTestSession(apiContext, USER_EMAIL, USER_NAME)
    sessionToken = session.token
    workspaceAlpha = await getWorkspaceId(apiContext)

    await apiContext.put(`${API_BASE}/api/test/workspace`, {
      data: { workspace_id: workspaceAlpha, name: ALPHA_NAME },
    })
  })

  test.afterAll(async () => {
    await apiContext?.dispose()
  })

  test('create a workspace, configure it, and switch back and forth', async ({
    page,
  }) => {
    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/settings')

    // The sidebar leads with the personal group, then one group per
    // administered workspace — Alpha only, for now.
    await expect(
      page.locator('[data-testid="settings-nav-group"][data-group="personal"]')
    ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
    await expect(settingsGroup(page, workspaceAlpha)).toContainText(ALPHA_NAME)

    // Only one workspace so far, so there is nothing to switch between and
    // the header switcher stays unmounted.
    await expect(page.getByTestId('workspace-switcher-trigger')).toHaveCount(0)

    // Create Beta.
    await page.getByTestId('settings-new-workspace').click()
    const dialog = page.getByRole('dialog')
    await dialog.getByLabel('Name').fill(BETA_NAME)
    await dialog.getByLabel('Timezone').selectOption('Europe/Lisbon')
    await dialog.getByRole('button', { name: 'Create' }).click()

    // Creating a workspace drops you into it: a group of its own in the
    // sidebar, and it becomes the active workspace.
    const betaGroup = page
      .locator('[data-testid="settings-nav-group"]')
      .filter({ hasText: BETA_NAME })
    await expect(betaGroup).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
    const workspaceBeta = await betaGroup.getAttribute('data-workspace-id')
    expect(workspaceBeta, 'new workspace group carries its id').toBeTruthy()
    await expect(page.getByTestId('current-workspace-name')).toHaveText(
      BETA_NAME
    )

    // Two workspaces now, so the switcher is mounted.
    await expect(
      page.getByTestId('workspace-switcher-trigger').first()
    ).toBeVisible()

    // Rename Beta and change its zone from its own settings section.
    await settingsGroup(page, workspaceBeta!)
      .getByRole('link', { name: 'General' })
      .click()
    await expect(page).toHaveURL(`/settings/workspaces/${workspaceBeta}/general`)
    // Scoped to the form: the (closed) new-workspace dialog stays mounted and
    // has a Timezone field of its own.
    const form = page.getByTestId('workspace-general-form')
    await form.getByLabel('Workspace name').fill(BETA_RENAMED)
    await form.getByLabel('Timezone').selectOption('Pacific/Auckland')
    await form.getByRole('button', { name: 'Save' }).click()

    // The rename lands everywhere the name is rendered — sidebar group and
    // header both read from the pool.
    await expect(settingsGroup(page, workspaceBeta!)).toContainText(BETA_RENAMED)
    await expect(page.getByTestId('current-workspace-name')).toHaveText(
      BETA_RENAMED
    )

    // Switch to Alpha. Both groups stay listed — settings shows every
    // workspace you administer, not just the active one.
    await switchToWorkspace(page, workspaceAlpha)
    await expect(page.getByTestId('current-workspace-name')).toHaveText(
      ALPHA_NAME
    )
    await expect(settingsGroup(page, workspaceAlpha)).toBeVisible()
    await expect(settingsGroup(page, workspaceBeta!)).toContainText(BETA_RENAMED)

    // Alpha's own section shows Alpha's values, not the ones we just typed
    // into Beta's form.
    await settingsGroup(page, workspaceAlpha)
      .getByRole('link', { name: 'General' })
      .click()
    await expect(form.getByLabel('Workspace name')).toHaveValue(ALPHA_NAME)
    await expect(form.getByLabel('Timezone')).toHaveValue('Europe/Amsterdam')

    // Switch back to Beta: the edits survived the round trip without a
    // reload.
    await switchToWorkspace(page, workspaceBeta!)
    await expect(page.getByTestId('current-workspace-name')).toHaveText(
      BETA_RENAMED
    )
    await settingsGroup(page, workspaceBeta!)
      .getByRole('link', { name: 'General' })
      .click()
    await expect(form.getByLabel('Workspace name')).toHaveValue(BETA_RENAMED)
    await expect(form.getByLabel('Timezone')).toHaveValue('Pacific/Auckland')
  })

  test('a workspace you are only a member of gets no settings group', async ({
    page,
    playwright,
  }) => {
    // Gamma is owned by someone else; our user joins as a plain member.
    const otherOwner = await newApiContext(playwright)
    await getTestSession(otherOwner, OTHER_OWNER_EMAIL, OTHER_OWNER_NAME)
    const workspaceGamma = await getWorkspaceId(otherOwner)
    await otherOwner.put(`${API_BASE}/api/test/workspace`, {
      data: { workspace_id: workspaceGamma, name: GAMMA_NAME },
    })
    await addMemberToWorkspace(otherOwner, workspaceGamma, USER_EMAIL)
    await otherOwner.dispose()

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/settings')

    // Alpha (owned) has a group; Gamma (member) does not — but it is still
    // switchable, so this isn't just "we never loaded it".
    await expect(settingsGroup(page, workspaceAlpha)).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })
    await expect(settingsGroup(page, workspaceGamma)).toHaveCount(0)

    await page.getByTestId('workspace-switcher-trigger').first().click()
    await expect(
      page
        .locator(
          `[data-testid="workspace-switcher-option"][data-workspace-id="${workspaceGamma}"]`
        )
        .first()
    ).toBeVisible()
  })
})
