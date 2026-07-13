import { describe, it, expect, beforeEach, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useWorkspaceStore } from '@/stores/workspace'
import { makeWorkspace, seedPool } from '@/test/factories'
import type { AuditLogEntry, AuditLogPage } from '@/types/auditLog'
import AuditLogPage_ from './AuditLogPage.vue'

const rawApiGet = vi.fn()
vi.mock('@/api/client', () => ({
  rawApi: {
    get: (...args: unknown[]) => rawApiGet(...args),
  },
}))

function makeEntry(overrides: Partial<AuditLogEntry> = {}): AuditLogEntry {
  return {
    id: 'ale-1',
    createdAt: '2026-07-10T10:00:00.000Z',
    actorKind: 'user',
    actorUserId: 'user-1',
    actorName: 'Olive Owner',
    service: 'Events::Update',
    subjectType: 'event',
    subjectId: 'evt-1',
    outcome: 'success',
    errorCode: null,
    errorMessage: null,
    actionParams: {},
    requestId: null,
    idempotencyKeyHash: null,
    ...overrides,
  }
}

function respondWith(page: AuditLogPage) {
  rawApiGet.mockResolvedValueOnce({ data: page, status: 200 })
}

function seedWorkspace(viewAllowed: boolean) {
  const pool = useObjectPoolStore()
  seedPool(
    pool,
    makeWorkspace({
      id: 'ws-1',
      permissions: {
        view_audit_log: viewAllowed
          ? { allowed: true }
          : { allowed: false, reason: 'not_workspace_owner' },
      },
    })
  )
  useWorkspaceStore().currentWorkspaceId = 'ws-1'
}

async function mountPage() {
  const wrapper = mount(AuditLogPage_)
  await flushPromises()
  return wrapper
}

describe('AuditLogPage', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    rawApiGet.mockReset()
  })

  it('shows the owner-only empty state for non-owners and does not fetch', async () => {
    seedWorkspace(false)

    const wrapper = await mountPage()

    expect(wrapper.find('[data-testid="audit-log-forbidden"]').exists()).toBe(
      true
    )
    expect(rawApiGet).not.toHaveBeenCalled()
  })

  it('renders entries with humanized action, actor, and outcome', async () => {
    seedWorkspace(true)
    respondWith({
      entries: [
        makeEntry({ id: 'e1', service: 'ChoreRosters::CreateAssignment' }),
        makeEntry({
          id: 'e2',
          service: 'Events::Delete',
          outcome: 'denied',
          errorCode: 'forbidden',
          actorKind: 'system',
          actorUserId: null,
          actorName: null,
        }),
      ],
      nextCursor: null,
    })

    const wrapper = await mountPage()

    expect(rawApiGet).toHaveBeenCalledWith('/workspaces/ws-1/audit-log')
    const list = wrapper.find('[data-testid="audit-log-list"]')
    expect(list.text()).toContain('Create assignment')
    expect(list.text()).toContain('Chore rosters')
    expect(list.text()).toContain('Olive Owner')
    expect(list.text()).toContain('System')
    expect(list.text()).toContain('denied')
  })

  it('expands a row to show the detail view', async () => {
    seedWorkspace(true)
    respondWith({
      entries: [
        makeEntry({
          id: 'e1',
          actionParams: { name: 'New name' },
          requestId: 'req-42',
          errorMessage: 'not allowed',
          outcome: 'error',
          errorCode: 'validation_error',
        }),
      ],
      nextCursor: null,
    })

    const wrapper = await mountPage()
    expect(wrapper.find('[data-testid="audit-log-detail-e1"]').exists()).toBe(
      false
    )

    await wrapper.find('[data-testid="audit-log-entry-e1"]').trigger('click')

    const detail = wrapper.find('[data-testid="audit-log-detail-e1"]')
    expect(detail.exists()).toBe(true)
    expect(detail.text()).toContain('Events::Update')
    expect(detail.text()).toContain('req-42')
    expect(detail.text()).toContain('not allowed')
    expect(detail.find('[data-testid="audit-log-params"]').text()).toContain(
      '"name": "New name"'
    )
  })

  it('pages older and newer via cursors', async () => {
    seedWorkspace(true)
    respondWith({
      entries: [makeEntry({ id: 'e1', service: 'Page::One' })],
      nextCursor: 'cursor-1',
    })

    const wrapper = await mountPage()
    expect(wrapper.text()).toContain('Page 1')
    expect(
      wrapper.find('[data-testid="audit-log-newer"]').attributes('disabled')
    ).toBeDefined()

    respondWith({
      entries: [makeEntry({ id: 'e2', service: 'Page::Two' })],
      nextCursor: null,
    })
    await wrapper.find('[data-testid="audit-log-older"]').trigger('click')
    await flushPromises()

    expect(rawApiGet).toHaveBeenLastCalledWith(
      '/workspaces/ws-1/audit-log?cursor=cursor-1'
    )
    expect(wrapper.text()).toContain('Page 2')
    expect(wrapper.text()).toContain('Two')
    expect(
      wrapper.find('[data-testid="audit-log-older"]').attributes('disabled')
    ).toBeDefined()

    respondWith({
      entries: [makeEntry({ id: 'e1', service: 'Page::One' })],
      nextCursor: 'cursor-1',
    })
    await wrapper.find('[data-testid="audit-log-newer"]').trigger('click')
    await flushPromises()

    expect(rawApiGet).toHaveBeenLastCalledWith('/workspaces/ws-1/audit-log')
    expect(wrapper.text()).toContain('Page 1')
  })

  it('shows a retry state when the fetch fails', async () => {
    seedWorkspace(true)
    rawApiGet.mockRejectedValueOnce({ message: 'boom', status: 500 })

    const wrapper = await mountPage()

    expect(wrapper.find('[data-testid="audit-log-error"]').exists()).toBe(true)
  })
})
