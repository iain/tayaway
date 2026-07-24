import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { makeMember, makeWorkspaceInvite } from '@/test/factories'
import type { PoolObject } from '@/types/pool'
import { useMembersStore } from './members'

vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: () => ({ currentWorkspaceId: 'ws-1' }),
}))

// Stand-in pool, so this file never loads the real store — it imports the
// api client, which is mocked here, and the cycle costs us the mock.
let pooled: PoolObject[] = []

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: (type: string) => pooled.filter((o) => o.objectType === type),
    importObjects: vi.fn(),
    remove: vi.fn(),
  }),
}))

vi.mock('@/stores/notifications', () => ({
  useNotificationsStore: () => ({ showError: vi.fn() }),
}))

// Mutable mock so individual tests can swap behaviour
let apiGetImpl: () => Promise<unknown> = async () => ({ objects: [] })
const apiGetUrls: string[] = []

vi.mock('@/api/client', async () => {
  const actual =
    await vi.importActual<typeof import('@/api/client')>('@/api/client')
  return {
    ...actual,
    api: {
      get: vi.fn().mockImplementation((url: string) => {
        apiGetUrls.push(url)
        return apiGetImpl()
      }),
    },
  }
})

// Everything the roster reads is derived from the pool by workspace id.
// Settings administers workspaces that aren't the active one, so the getters
// take an id and only default to the active workspace.
describe('members store — workspace scoping', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    pooled = []
    apiGetUrls.length = 0
    apiGetImpl = async () => ({ data: { objects: [] }, status: 200 })
  })

  it('lists members of the workspace asked for, not the active one', () => {
    pooled = [
      makeMember({ id: 'mem-here', workspaceId: 'ws-1', name: 'Alice' }),
      makeMember({ id: 'mem-there', workspaceId: 'ws-2', name: 'Bob' }),
    ]

    const store = useMembersStore()

    expect(store.membersIn('ws-2').map((m) => m.name)).toEqual(['Bob'])
    expect(store.members.map((m) => m.name)).toEqual(['Alice'])
  })

  it('lists pending invites of the workspace asked for', () => {
    pooled = [
      makeWorkspaceInvite({ id: 'inv-here', workspaceId: 'ws-1' }),
      makeWorkspaceInvite({
        id: 'inv-there',
        workspaceId: 'ws-2',
        email: 'carol@example.com',
      }),
      makeWorkspaceInvite({
        id: 'inv-accepted',
        workspaceId: 'ws-2',
        email: 'dan@example.com',
        acceptedAt: '2026-01-02T00:00:00.000Z',
      }),
    ]

    const store = useMembersStore()

    expect(store.pendingInvitesIn('ws-2').map((i) => i.email)).toEqual([
      'carol@example.com',
    ])
  })

  it('fetches the roster for a workspace the client is not subscribed to', async () => {
    const store = useMembersStore()

    await store.fetchMembers('ws-2')

    expect(apiGetUrls).toEqual(['/members?workspace_id=ws-2'])
  })
})

describe('members store — fetchInvites', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    apiGetImpl = async () => ({ data: { objects: [] }, status: 200 })
    vi.spyOn(console, 'warn').mockImplementation(() => undefined)
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('silently ignores 403 errors', async () => {
    apiGetImpl = async () => {
      const err: { message: string; status: number } = {
        message: 'Forbidden',
        status: 403,
      }
      throw err
    }

    const store = useMembersStore()
    await expect(store.fetchInvites()).resolves.toBeUndefined()
    expect(console.warn).not.toHaveBeenCalled()
  })

  it('logs non-403 errors to console.warn', async () => {
    apiGetImpl = async () => {
      const err: { message: string; status: number } = {
        message: 'Internal Server Error',
        status: 500,
      }
      throw err
    }

    const store = useMembersStore()
    await store.fetchInvites()

    expect(console.warn).toHaveBeenCalledWith(
      'Failed to fetch invites',
      expect.objectContaining({ status: 500 })
    )
  })

  it('logs network errors (no status) to console.warn', async () => {
    apiGetImpl = async () => {
      throw new TypeError('Failed to fetch')
    }

    const store = useMembersStore()
    await store.fetchInvites()

    expect(console.warn).toHaveBeenCalledWith(
      'Failed to fetch invites',
      expect.any(TypeError)
    )
  })
})
