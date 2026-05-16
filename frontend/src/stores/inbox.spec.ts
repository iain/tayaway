import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useInboxStore } from './inbox'
import { useObjectPoolStore } from './objectPool'
import type { PoolNotification } from '@/types/pool'
import type { ApiResponse } from '@/api/client'

function makeNotification(
  overrides: Partial<PoolNotification> = {}
): PoolNotification {
  return {
    id: 'n-1',
    objectType: 'notification',
    userId: 'user-1',
    workspaceId: 'ws-1',
    kind: 'expense_added',
    data: { title: 'New expense', body: 'Alice added Pizza' },
    readAt: null,
    createdAt: '2026-05-10T10:00:00.000Z',
    updatedAt: '2026-05-10T10:00:00.000Z',
    ...overrides,
  }
}

function okResponse<T>(data: T): ApiResponse<T> {
  return { data, status: 200 }
}

const { rawApiMock } = vi.hoisted(() => ({
  rawApiMock: {
    get: vi.fn<
      (path: string, options?: unknown) => Promise<ApiResponse<unknown>>
    >(),
    put: vi.fn<
      (
        path: string,
        body?: unknown,
        options?: unknown
      ) => Promise<ApiResponse<unknown>>
    >(),
    post: vi.fn<
      (
        path: string,
        body?: unknown,
        options?: unknown
      ) => Promise<ApiResponse<unknown>>
    >(),
  },
}))

vi.mock('@/api/client', () => ({
  rawApi: rawApiMock,
}))

const { toastMock } = vi.hoisted(() => ({
  toastMock: {
    showInfo: vi.fn(),
    showError: vi.fn(),
  },
}))

vi.mock('@/stores/notifications', () => ({
  useNotificationsStore: () => toastMock,
}))

describe('inbox store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    rawApiMock.get.mockReset()
    rawApiMock.put.mockReset()
    rawApiMock.post.mockReset()
    rawApiMock.put.mockResolvedValue(okResponse({ ok: true }))
    rawApiMock.post.mockResolvedValue(okResponse({ ok: true }))
    toastMock.showInfo.mockReset()
    toastMock.showError.mockReset()
  })

  describe('derived from the object pool', () => {
    it('exposes notifications sorted newest-first', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeNotification({ id: 'old', createdAt: '2026-05-09T10:00:00.000Z' }),
        makeNotification({ id: 'new', createdAt: '2026-05-10T10:00:00.000Z' }),
      ], { scope: "workspace:test" })

      const inbox = useInboxStore()

      expect(inbox.notifications.map((n) => n.id)).toEqual(['new', 'old'])
    })

    it('reports the unread count from the pool', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeNotification({ id: 'a' }),
        makeNotification({ id: 'b' }),
        makeNotification({ id: 'c', readAt: '2026-05-10T11:00:00.000Z' }),
      ], { scope: "workspace:test" })

      const inbox = useInboxStore()

      expect(inbox.unreadCount).toBe(2)
    })

    it('absorbs new notifications delivered after the store is created', () => {
      const pool = useObjectPoolStore()
      const inbox = useInboxStore()
      expect(inbox.notifications).toEqual([])

      pool.importObjects([makeNotification({ id: 'pushed' })], { scope: "workspace:test" })

      expect(inbox.notifications.map((n) => n.id)).toEqual(['pushed'])
      expect(inbox.unreadCount).toBe(1)
    })

    it('groups unread counts by workspace so other workspaces can be badged', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeNotification({ id: 'a', workspaceId: 'ws-1' }),
        makeNotification({ id: 'b', workspaceId: 'ws-1' }),
        makeNotification({ id: 'c', workspaceId: 'ws-2' }),
        makeNotification({
          id: 'd',
          workspaceId: 'ws-2',
          readAt: '2026-05-10T11:00:00.000Z',
        }),
      ], { scope: "workspace:test" })

      const { useWorkspaceStore } = await import('./workspace')
      useWorkspaceStore().initialize(['ws-current'])

      const inbox = useInboxStore()
      expect(inbox.unreadCountByOtherWorkspace.get('ws-1')).toBe(2)
      expect(inbox.unreadCountByOtherWorkspace.get('ws-2')).toBe(1)
    })

    it('excludes the current workspace from the unread-by-other-workspace map', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeNotification({ id: 'a', workspaceId: 'ws-current' }),
        makeNotification({ id: 'b', workspaceId: 'ws-other' }),
      ], { scope: "workspace:test" })

      const { useWorkspaceStore } = await import('./workspace')
      useWorkspaceStore().initialize(['ws-current'])

      const inbox = useInboxStore()
      expect(inbox.unreadCountByOtherWorkspace.get('ws-current')).toBeUndefined()
      expect(inbox.unreadCountByOtherWorkspace.get('ws-other')).toBe(1)
    })
  })

  describe('load', () => {
    it('hydrates the object pool from the GET response', async () => {
      rawApiMock.get.mockResolvedValueOnce(
        okResponse({ objects: [makeNotification({ id: 'fetched' })] })
      )

      const inbox = useInboxStore()
      await inbox.load()

      const pool = useObjectPoolStore()
      expect(pool.getAll('notification').map((n) => n.id)).toEqual(['fetched'])
      expect(inbox.notifications.map((n) => n.id)).toEqual(['fetched'])
    })
  })

  describe('markRead', () => {
    it('optimistically marks the notification read in the pool', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeNotification({ id: 'n-1' })], { scope: "workspace:test" })

      const inbox = useInboxStore()
      await inbox.markRead('n-1')

      expect(pool.get('notification', 'n-1')?.readAt).not.toBeNull()
      expect(rawApiMock.put).toHaveBeenCalledWith(
        '/notifications/n-1/read',
        {},
        expect.objectContaining({ silent: true })
      )
    })

    it('rolls back the readAt change if the request fails', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeNotification({ id: 'n-1' })], { scope: "workspace:test" })
      rawApiMock.put.mockRejectedValueOnce(new Error('boom'))

      const inbox = useInboxStore()
      await inbox.markRead('n-1')

      expect(pool.get('notification', 'n-1')?.readAt).toBeNull()
      expect(inbox.unreadCount).toBe(1)
    })

    it('is a no-op for an already-read notification', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeNotification({ id: 'n-1', readAt: '2026-05-10T11:00:00.000Z' }),
      ], { scope: "workspace:test" })

      const inbox = useInboxStore()
      await inbox.markRead('n-1')

      expect(rawApiMock.put).not.toHaveBeenCalled()
    })
  })

  describe('markAllRead', () => {
    it('marks every unread notification read in the pool', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeNotification({ id: 'a' }),
        makeNotification({ id: 'b' }),
        makeNotification({ id: 'c', readAt: '2026-05-10T11:00:00.000Z' }),
      ], { scope: "workspace:test" })

      const inbox = useInboxStore()
      await inbox.markAllRead()

      expect(pool.get('notification', 'a')?.readAt).not.toBeNull()
      expect(pool.get('notification', 'b')?.readAt).not.toBeNull()
      expect(inbox.unreadCount).toBe(0)
    })

    it('rolls each notification back if the request fails', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeNotification({ id: 'a' }),
        makeNotification({ id: 'b' }),
      ], { scope: "workspace:test" })
      rawApiMock.put.mockRejectedValueOnce(new Error('boom'))

      const inbox = useInboxStore()
      await inbox.markAllRead()

      expect(pool.get('notification', 'a')?.readAt).toBeNull()
      expect(pool.get('notification', 'b')?.readAt).toBeNull()
      expect(inbox.unreadCount).toBe(2)
    })
  })

  describe('silenceKind', () => {
    // The bell's "Stop sending me these" must persist immediately so the
    // preference survives the user closing the tab or navigating away
    // inside the Undo window. The undo path POSTs unsilence to restore.
    it('fires the silence POST synchronously, before the undo window expires', async () => {
      const inbox = useInboxStore()
      inbox.silenceKind('expense_added', 'Silenced')
      await Promise.resolve()

      expect(rawApiMock.post).toHaveBeenCalledWith(
        '/notifications/preferences/silence',
        { kind: 'expense_added' },
        expect.objectContaining({ silent: true })
      )
    })

    it('shows an undo toast labelled Undo', () => {
      const inbox = useInboxStore()
      inbox.silenceKind('expense_added', 'Silenced')

      expect(toastMock.showInfo).toHaveBeenCalledWith(
        'Silenced',
        expect.objectContaining({ actionLabel: 'Undo' })
      )
    })

    it('invokes the unsilence endpoint when the Undo action runs', async () => {
      const inbox = useInboxStore()
      inbox.silenceKind('expense_added', 'Silenced')
      await Promise.resolve()

      const lastCall = toastMock.showInfo.mock.calls.at(-1)
      const options = lastCall?.[1] as { action: () => void }
      options.action()
      await Promise.resolve()

      expect(rawApiMock.post).toHaveBeenCalledWith(
        '/notifications/preferences/unsilence',
        { kind: 'expense_added' },
        expect.objectContaining({ silent: true })
      )
    })

    it('shows an error toast when the silence POST fails', async () => {
      rawApiMock.post.mockRejectedValueOnce(new Error('boom'))
      const inbox = useInboxStore()
      inbox.silenceKind('expense_added', 'Silenced')
      await Promise.resolve()
      await Promise.resolve()

      expect(toastMock.showError).toHaveBeenCalled()
    })

    it('also marks the source notification read when given an id', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeNotification({ id: 'n-1' })], { scope: "workspace:test" })
      const inbox = useInboxStore()
      inbox.silenceKind('expense_added', 'Silenced', 'n-1')
      await Promise.resolve()

      expect(pool.get('notification', 'n-1')?.readAt).not.toBeNull()
    })
  })
})
