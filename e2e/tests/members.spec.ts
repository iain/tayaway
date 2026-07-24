import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getObjectByType,
  getTestSession,
  setupAuthenticatedPage,
  getWorkspaceId,
  addMemberToWorkspace,
  newApiContext,
} from '../helpers'

const OWNER_EMAIL = 'e2e-members-owner@example.com'
const OWNER_NAME = 'E2E Members Owner'
const ADMIN_EMAIL = 'e2e-members-admin@example.com'
const ADMIN_NAME = 'E2E Members Admin'
const MEMBER_EMAIL = 'e2e-members-member@example.com'
const MEMBER_NAME = 'E2E Members Member'

test.describe('Member Role Management', () => {
  // Tests mutate shared membership roles — must run serially to avoid races
  test.describe.configure({ mode: 'serial' })

  test.describe('Members API', () => {
    let ownerContext: APIRequestContext
    let adminContext: APIRequestContext
    let memberContext: APIRequestContext
    let workspaceId: string
    let adminMemberId: string
    let memberMemberId: string

    test.beforeAll(async ({ playwright }) => {
      // Create owner
      ownerContext = await newApiContext(playwright)
      await getTestSession(ownerContext, OWNER_EMAIL, OWNER_NAME)
      workspaceId = await getWorkspaceId(ownerContext)

      // Create admin user and add to workspace
      adminContext = await newApiContext(playwright)
      await getTestSession(adminContext, ADMIN_EMAIL, ADMIN_NAME)
      adminMemberId = await addMemberToWorkspace(
        ownerContext,
        workspaceId,
        ADMIN_EMAIL
      )

      // Create regular member and add to workspace
      memberContext = await newApiContext(playwright)
      await getTestSession(memberContext, MEMBER_EMAIL, MEMBER_NAME)
      memberMemberId = await addMemberToWorkspace(
        ownerContext,
        workspaceId,
        MEMBER_EMAIL
      )

      // Ensure correct roles (handles stale state from previous failed runs)
      await ownerContext.put(`${API_BASE}/api/members/${adminMemberId}`, {
        data: { role: 'admin' },
      })
      await ownerContext.put(`${API_BASE}/api/members/${memberMemberId}`, {
        data: { role: 'member' },
      })
    })

    test.afterAll(async () => {
      await ownerContext?.dispose()
      await adminContext?.dispose()
      await memberContext?.dispose()
    })

    test('PUT /api/members/:id requires auth', async ({ request }) => {
      const response = await request.put(`${API_BASE}/api/members/some-id`, {
        data: { role: 'admin' },
      })
      expect(response.status()).toBe(401)
    })

    test('owner can change member to admin', async () => {
      const response = await ownerContext.put(
        `${API_BASE}/api/members/${memberMemberId}`,
        { data: { role: 'admin' } }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const member = getObjectByType(body.objects, 'member')
      expect(member?.role).toBe('admin')

      // Restore to member
      await ownerContext.put(`${API_BASE}/api/members/${memberMemberId}`, {
        data: { role: 'member' },
      })
    })

    test('admin can change member role but not owner role', async () => {
      // Admin can change member to admin
      const promoteResp = await adminContext.put(
        `${API_BASE}/api/members/${memberMemberId}`,
        { data: { role: 'admin' } }
      )
      expect(promoteResp.ok()).toBeTruthy()

      // Restore
      await adminContext.put(`${API_BASE}/api/members/${memberMemberId}`, {
        data: { role: 'member' },
      })

      // Admin cannot get the owner's membership to try to change it
      // (they would need the owner's member ID)
      // Let's find the owner's member ID
      const wsResp = await adminContext.get(`${API_BASE}/api/workspaces`)
      const wsBody = await wsResp.json()
      const members = wsBody.objects.filter(
        (o: { objectType: string }) => o.objectType === 'member'
      )
      const ownerMember = members.find(
        (m: { email: string }) => m.email === OWNER_EMAIL
      )
      if (ownerMember) {
        const response = await adminContext.put(
          `${API_BASE}/api/members/${ownerMember.id}`,
          { data: { role: 'member' } }
        )
        expect(response.status()).toBe(403)
      }
    })

    test('regular member cannot change roles', async () => {
      const response = await memberContext.put(
        `${API_BASE}/api/members/${adminMemberId}`,
        { data: { role: 'member' } }
      )
      expect(response.status()).toBe(403)
    })
  })

  // The members page is the friendly directory: who's here, how to reach
  // them. Everything that *changes* the roster — roles, invitations — lives
  // in the workspace's settings, behind the same admin/owner bar the API
  // enforces. Admins get a link across; everyone else sees a page with no
  // controls on it at all.
  test.describe('Members UI - Role management', () => {
    let ownerToken: string
    let ownerContext: APIRequestContext
    let memberToken: string
    let workspaceId: string

    test.beforeAll(async ({ playwright }) => {
      ownerContext = await newApiContext(playwright)
      const { token } = await getTestSession(
        ownerContext,
        OWNER_EMAIL,
        OWNER_NAME
      )
      ownerToken = token
      workspaceId = await getWorkspaceId(ownerContext)

      // Ensure another member exists so the role dropdown appears
      const uiMemberContext = await newApiContext(playwright)
      const memberSession = await getTestSession(
        uiMemberContext,
        MEMBER_EMAIL,
        MEMBER_NAME
      )
      memberToken = memberSession.token
      const uiMemberId = await addMemberToWorkspace(
        ownerContext,
        workspaceId,
        MEMBER_EMAIL
      )
      await ownerContext.put(`${API_BASE}/api/members/${uiMemberId}`, {
        data: { role: 'member' },
      })
      await uiMemberContext.dispose()
    })

    test.afterAll(async () => {
      await ownerContext.dispose()
    })

    test('members page shows member list with roles', async ({ page }) => {
      await setupAuthenticatedPage(page, ownerToken)
      await page.goto('/members')

      // Wait for members list to load
      await expect(page.getByTestId('members-list')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Should see the owner's name
      await expect(page.getByText(OWNER_NAME)).toBeVisible()
    })

    test('members page shows vCard download button on each member', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, ownerToken)
      await page.goto('/members')

      await expect(page.getByTestId('members-list')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Each member card should have a download vCard button
      const downloadButtons = page.getByTestId('download-vcard-button')
      const count = await downloadButtons.count()
      expect(count).toBeGreaterThanOrEqual(1)

      // Verify the button has the correct title
      await expect(downloadButtons.first()).toHaveAttribute(
        'title',
        'Download contact card'
      )
    })

    test('vCard download triggers file download', async ({ page }) => {
      await setupAuthenticatedPage(page, ownerToken)
      await page.goto('/members')

      await expect(page.getByTestId('members-list')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Listen for the download event
      const downloadPromise = page.waitForEvent('download')
      await page.getByTestId('download-vcard-button').first().click()
      const download = await downloadPromise

      // Verify the downloaded file has a .vcf extension
      expect(download.suggestedFilename()).toMatch(/\.vcf$/)
    })

    test('the members page is read-only, and points admins at settings', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, ownerToken)
      await page.goto('/members')

      await expect(page.getByTestId('members-list')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Roles are shown as badges here, never as editors.
      await expect(page.getByTestId('member-role-select')).toHaveCount(0)
      await expect(page.getByTestId('member-role').first()).toBeVisible()
      await expect(page.getByTestId('invite-member-button')).toHaveCount(0)

      // The one admin affordance left is the way across.
      await page.getByTestId('manage-members-link').click()
      await expect(page).toHaveURL(`/settings/workspaces/${workspaceId}/members`)
    })

    test('owner can change member role from workspace settings', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, ownerToken)
      await page.goto(`/settings/workspaces/${workspaceId}/members`)

      await expect(page.getByTestId('workspace-members')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Find a member with a role select dropdown (not the owner themselves)
      const roleSelect = page.getByTestId('member-role-select').first()
      await expect(roleSelect).toBeVisible()

      // Read the current value and select the opposite to guarantee a change event
      const currentRole = await roleSelect.inputValue()
      const newRole = currentRole === 'admin' ? 'member' : 'admin'

      // Change role and wait for API response
      await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/members/') &&
            resp.request().method() === 'PUT'
        ),
        roleSelect.selectOption(newRole),
      ])

      // The select should now show the new role
      await expect(roleSelect).toHaveValue(newRole)

      // Restore, so the ordering of tests in this file doesn't matter.
      await Promise.all([
        page.waitForResponse(
          (resp) =>
            resp.url().includes('/api/members/') &&
            resp.request().method() === 'PUT'
        ),
        roleSelect.selectOption(currentRole),
      ])
    })

    test('a plain member gets the directory and no way into settings', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, memberToken)
      // Every test user owns a workspace of their own, and that's the one
      // they'd otherwise land on — where they are the owner. Pin the shared
      // one, which is the workspace they're merely a member of.
      await page.addInitScript((id) => {
        localStorage.setItem('current_workspace_id', id)
      }, workspaceId)
      await page.goto('/members')

      await expect(page.getByTestId('members-list')).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(page.getByTestId('manage-members-link')).toHaveCount(0)
      await expect(page.getByTestId('member-role-select')).toHaveCount(0)

      // Settings lists no group for a workspace you don't administer, so
      // there is no Members section to reach either.
      await page.goto('/settings')
      await expect(
        page.locator('[data-testid="settings-nav-group"][data-group="personal"]')
      ).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
      await expect(
        page.locator(
          `[data-testid="settings-nav-group"][data-workspace-id="${workspaceId}"]`
        )
      ).toHaveCount(0)
    })
  })
})
