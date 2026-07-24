import { describe, it, expect, beforeEach, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useWorkspaceStore } from '@/stores/workspace'
import { useMembersStore } from '@/stores/members'
import { makeMember, makeWorkspace, seedPool } from '@/test/factories'
import SettingsWorkspaceMembersPage from './SettingsWorkspaceMembersPage.vue'

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { id: 'ws-2' } }),
}))

let pool: ReturnType<typeof useObjectPoolStore>

// The counterpart to the members directory: this is where the roster is
// actually administered, for any workspace you own — not just the active one.
describe('SettingsWorkspaceMembersPage', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
    pool = useObjectPoolStore()
    useWorkspaceStore().currentWorkspaceId = 'ws-1'
  })

  it('administers the workspace in the route, not the active one', async () => {
    seedPool(
      pool,
      makeWorkspace({ id: 'ws-2', name: 'Other Group' }),
      makeMember({ id: 'mem-here', workspaceId: 'ws-1', name: 'Alice' }),
      makeMember({ id: 'mem-there', workspaceId: 'ws-2', name: 'Bob' })
    )
    const store = useMembersStore()
    const fetchMembers = vi
      .spyOn(store, 'fetchMembers')
      .mockResolvedValue(undefined)
    vi.spyOn(store, 'fetchInvites').mockResolvedValue(undefined)

    const page = mount(SettingsWorkspaceMembersPage)
    await flushPromises()

    expect(page.text()).toContain('Bob')
    expect(page.text()).not.toContain('Alice')
    // The pool only carries our own membership for a workspace we aren't
    // subscribed to, so the page has to ask for the rest.
    expect(fetchMembers).toHaveBeenCalledWith('ws-2')
  })

  it('changes a role through the store', async () => {
    seedPool(
      pool,
      makeWorkspace({ id: 'ws-2' }),
      makeMember({
        id: 'mem-there',
        workspaceId: 'ws-2',
        role: 'member',
        permissions: {
          change_role: { allowed: true },
          availableRoles: ['member', 'admin'],
        },
      })
    )
    const store = useMembersStore()
    vi.spyOn(store, 'fetchMembers').mockResolvedValue(undefined)
    vi.spyOn(store, 'fetchInvites').mockResolvedValue(undefined)
    const updateMemberRole = vi
      .spyOn(store, 'updateMemberRole')
      .mockResolvedValue({ queued: false, data: {} })

    const page = mount(SettingsWorkspaceMembersPage)
    await page.find('[data-testid="member-role-select"]').setValue('admin')

    expect(updateMemberRole).toHaveBeenCalledWith('mem-there', 'admin')
  })

  it('shows a plain badge for a role that is not ours to change', () => {
    seedPool(
      pool,
      makeWorkspace({ id: 'ws-2' }),
      makeMember({
        id: 'mem-there',
        workspaceId: 'ws-2',
        role: 'owner',
        permissions: {
          change_role: { allowed: false, reason: 'cannot_change_owner' },
        },
      })
    )
    const store = useMembersStore()
    vi.spyOn(store, 'fetchMembers').mockResolvedValue(undefined)
    vi.spyOn(store, 'fetchInvites').mockResolvedValue(undefined)

    const page = mount(SettingsWorkspaceMembersPage)

    expect(page.find('[data-testid="member-role-select"]').exists()).toBe(false)
    expect(page.find('[data-testid="member-role"]').text()).toBe('owner')
  })
})
