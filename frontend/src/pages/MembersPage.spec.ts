import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useWorkspaceStore } from '@/stores/workspace'
import { makeMember, makeWorkspace, seedPool } from '@/test/factories'
import MembersPage from './MembersPage.vue'

const RouterLinkStub = {
  props: ['to'],
  template: '<a :href="to"><slot /></a>',
}

function mountPage() {
  return mount(MembersPage, {
    global: { stubs: { RouterLink: RouterLinkStub } },
  })
}

let pool: ReturnType<typeof useObjectPoolStore>

// The directory is for everyone: who's in the group and how to reach them.
// Anything that changes the roster belongs to the workspace's settings.
describe('MembersPage', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
    pool = useObjectPoolStore()
    useWorkspaceStore().currentWorkspaceId = 'ws-1'
  })

  it('shows roles as badges, never as editors', () => {
    seedPool(
      pool,
      makeWorkspace({ id: 'ws-1' }),
      makeMember({
        id: 'mem-1',
        role: 'admin',
        permissions: { change_role: { allowed: true } },
      })
    )

    const page = mountPage()

    expect(page.find('[data-testid="member-role-select"]').exists()).toBe(false)
    expect(page.find('[data-testid="member-role"]').text()).toBe('admin')
  })

  it('offers admins the way across to settings', () => {
    seedPool(
      pool,
      makeWorkspace({
        id: 'ws-1',
        permissions: { manage_members: { allowed: true } },
      }),
      makeMember({ id: 'mem-1' })
    )

    const page = mountPage()

    expect(
      page.find('[data-testid="manage-members-link"]').attributes('href')
    ).toBe('/settings/workspaces/ws-1/members')
  })

  it('offers nothing to a member who cannot manage the roster', () => {
    seedPool(
      pool,
      makeWorkspace({
        id: 'ws-1',
        permissions: {
          manage_members: { allowed: false, reason: 'not_admin_or_owner' },
        },
      }),
      makeMember({ id: 'mem-1' })
    )

    const page = mountPage()

    expect(page.find('[data-testid="manage-members-link"]').exists()).toBe(
      false
    )
  })
})
