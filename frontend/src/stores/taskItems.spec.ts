import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useTaskItemsStore } from './taskItems'
import { useObjectPoolStore } from './objectPool'
import { useWorkspaceStore } from './workspace'
import { CommandQueuedError } from '@/stores/commandQueue'
import type { ObjectTypeMap } from '@/types/pool'
import type { ApiResponse } from '@/api/client'

function makeTaskItem(
  overrides: Partial<ObjectTypeMap['taskItem']> = {}
): ObjectTypeMap['taskItem'] {
  return {
    id: 'item-1',
    objectType: 'taskItem',
    taskListId: 'list-1',
    userId: 'user-1',
    content: 'Buy groceries',
    completedAt: null,
    position: 1000,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function okResponse<T>(data: T): ApiResponse<T> {
  return { data, status: 200 }
}

let enqueueImpl: () => Promise<ApiResponse<unknown>> = async () =>
  okResponse({ objects: [] })

vi.mock('@/stores/commandQueue', async () => {
  const actual = await vi.importActual<typeof import('@/stores/commandQueue')>(
    '@/stores/commandQueue'
  )
  return {
    ...actual,
    useCommandQueueStore: () => ({
      enqueue: vi.fn().mockImplementation(() => enqueueImpl()),
    }),
  }
})

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({ currentUserId: 'user-1' }),
}))

describe('taskItems store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    // Optimistic temp task items are scope-less; useMutation tags them with
    // the active workspace's scope and throws if none is set.
    localStorage.setItem('current_workspace_id', 'test')
    useWorkspaceStore().initialize(['test'])
    enqueueImpl = async () => okResponse({ objects: [] })
  })

  describe('addItem', () => {
    it('inserts a temp task item into the pool optimistically', async () => {
      const pool = useObjectPoolStore()
      const store = useTaskItemsStore()

      let itemDuringCall: ObjectTypeMap['taskItem'] | undefined
      enqueueImpl = async () => {
        itemDuringCall = pool.getAll('taskItem')[0]
        return okResponse({ objects: [] })
      }

      const { itemId } = await store.addItem('list-1', 'Pack bags')

      expect(itemDuringCall).toBeDefined()
      expect(itemDuringCall!.content).toBe('Pack bags')
      expect(itemDuringCall!.taskListId).toBe('list-1')
      expect(itemDuringCall!.id).toBe(itemId)
      expect(itemDuringCall!.completedAt).toBeNull()
    })

    it('keeps the temp item when request is queued offline', async () => {
      const pool = useObjectPoolStore()
      const store = useTaskItemsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      const { itemId, queued } = await store.addItem('list-1', 'Pack bags')

      expect(queued).toBe(true)
      expect(pool.get('taskItem', itemId)).toBeDefined()
    })

    it('removes the temp item on server error', async () => {
      const pool = useObjectPoolStore()
      const store = useTaskItemsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(store.addItem('list-1', 'Pack bags')).rejects.toThrow(
        'Server error'
      )

      expect(pool.getAll('taskItem')).toHaveLength(0)
      expect(store.error).toBe('Failed to add item')
    })
  })

  describe('updateItem', () => {
    it('optimistically updates content', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeTaskItem({ content: 'Old content' })], {
        scope: Scope.workspace('test'),
      })
      const store = useTaskItemsStore()

      let contentDuringCall: string | undefined
      enqueueImpl = async () => {
        contentDuringCall = pool.get('taskItem', 'item-1')?.content
        return okResponse({ objects: [] })
      }

      await store.updateItem('list-1', 'item-1', { content: 'New content' })

      expect(contentDuringCall).toBe('New content')
    })

    it('sets completedAt to a timestamp when completing', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeTaskItem({ completedAt: null })], {
        scope: Scope.workspace('test'),
      })
      const store = useTaskItemsStore()

      let completedAtDuringCall: string | null | undefined
      enqueueImpl = async () => {
        completedAtDuringCall = pool.get('taskItem', 'item-1')?.completedAt
        return okResponse({ objects: [] })
      }

      await store.updateItem('list-1', 'item-1', { completed: true })

      expect(completedAtDuringCall).not.toBeNull()
      expect(typeof completedAtDuringCall).toBe('string')
    })

    it('sets completedAt to null when uncompleting', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [makeTaskItem({ completedAt: '2026-01-05T10:00:00.000Z' })],
        { scope: Scope.workspace('test') }
      )
      const store = useTaskItemsStore()

      let completedAtDuringCall: string | null | undefined
      enqueueImpl = async () => {
        completedAtDuringCall = pool.get('taskItem', 'item-1')?.completedAt
        return okResponse({ objects: [] })
      }

      await store.updateItem('list-1', 'item-1', { completed: false })

      expect(completedAtDuringCall).toBeNull()
    })

    it('rolls back update on server error', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeTaskItem({ content: 'Original' })], {
        scope: Scope.workspace('test'),
      })
      const store = useTaskItemsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(
        store.updateItem('list-1', 'item-1', { content: 'Changed' })
      ).rejects.toThrow()

      expect(pool.get('taskItem', 'item-1')?.content).toBe('Original')
      expect(pool.hasPending('taskItem', 'item-1')).toBe(false)
    })

    it('keeps pending update when queued offline', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeTaskItem({ content: 'Original' })], {
        scope: Scope.workspace('test'),
      })
      const store = useTaskItemsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      await store.updateItem('list-1', 'item-1', { content: 'Changed' })

      expect(pool.get('taskItem', 'item-1')?.content).toBe('Changed')
      expect(pool.hasPending('taskItem', 'item-1')).toBe(true)
    })
  })

  describe('repositionItem', () => {
    it('optimistically updates the position', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeTaskItem({ position: 1000 })], {
        scope: Scope.workspace('test'),
      })
      const store = useTaskItemsStore()

      let positionDuringCall: number | undefined
      enqueueImpl = async () => {
        positionDuringCall = pool.get('taskItem', 'item-1')?.position
        return okResponse({ objects: [] })
      }

      // Place between positions 500 and 1000
      await store.repositionItem('list-1', 'item-1', 500, 1000)

      // New position should be between 500 and 1000
      expect(positionDuringCall).toBeGreaterThan(500)
      expect(positionDuringCall).toBeLessThan(1000)
    })

    it('updates taskListId when moving across lists', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeTaskItem({ taskListId: 'list-1' })], {
        scope: Scope.workspace('test'),
      })
      const store = useTaskItemsStore()

      let listDuringCall: string | undefined
      enqueueImpl = async () => {
        listDuringCall = pool.get('taskItem', 'item-1')?.taskListId
        return okResponse({ objects: [] })
      }

      await store.repositionItem('list-1', 'item-1', null, null, 'list-2')

      expect(listDuringCall).toBe('list-2')
    })

    it('does not change taskListId when staying in same list', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeTaskItem({ taskListId: 'list-1' })], {
        scope: Scope.workspace('test'),
      })
      const store = useTaskItemsStore()

      let listDuringCall: string | undefined
      enqueueImpl = async () => {
        listDuringCall = pool.get('taskItem', 'item-1')?.taskListId
        return okResponse({ objects: [] })
      }

      await store.repositionItem('list-1', 'item-1', null, null, 'list-1')

      expect(listDuringCall).toBe('list-1')
    })
  })

  describe('deleteItem', () => {
    it('optimistically removes the item from the pool', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeTaskItem()], { scope: Scope.workspace('test') })
      const store = useTaskItemsStore()

      let presentDuringCall: boolean | undefined
      enqueueImpl = async () => {
        presentDuringCall = pool.get('taskItem', 'item-1') !== undefined
        return okResponse({ objects: [] })
      }

      await store.deleteItem('list-1', 'item-1')

      expect(presentDuringCall).toBe(false)
      expect(pool.get('taskItem', 'item-1')).toBeUndefined()
    })

    it('restores the item when the API call fails', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeTaskItem()], { scope: Scope.workspace('test') })
      const store = useTaskItemsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(store.deleteItem('list-1', 'item-1')).rejects.toThrow(
        'Server error'
      )

      expect(pool.get('taskItem', 'item-1')).toBeDefined()
      expect(store.error).toBe('Failed to delete item')
    })

    it('keeps the item removed when queued offline', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeTaskItem()], { scope: Scope.workspace('test') })
      const store = useTaskItemsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      await store.deleteItem('list-1', 'item-1')

      expect(pool.get('taskItem', 'item-1')).toBeUndefined()
    })
  })

  describe('clearCompleted', () => {
    it('optimistically removes completed items from the pool', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeTaskItem({
            id: 'item-1',
            completedAt: '2026-01-05T10:00:00.000Z',
          }),
          makeTaskItem({
            id: 'item-2',
            completedAt: '2026-01-06T10:00:00.000Z',
          }),
        ],
        { scope: Scope.workspace('test') }
      )
      const store = useTaskItemsStore()

      let itemsDuringCall: ObjectTypeMap['taskItem'][] | undefined
      enqueueImpl = async () => {
        itemsDuringCall = pool.getAll('taskItem')
        return okResponse({ objects: [] })
      }

      await store.clearCompleted('list-1', ['item-1', 'item-2'])

      expect(itemsDuringCall).toHaveLength(0)
      expect(pool.getAll('taskItem')).toHaveLength(0)
    })

    it('restores completed items on server error', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeTaskItem({
            id: 'item-1',
            completedAt: '2026-01-05T10:00:00.000Z',
          }),
        ],
        { scope: Scope.workspace('test') }
      )
      const store = useTaskItemsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(store.clearCompleted('list-1', ['item-1'])).rejects.toThrow(
        'Server error'
      )

      expect(pool.get('taskItem', 'item-1')).toBeDefined()
      expect(store.error).toBe('Failed to clear completed items')
    })

    it('keeps completed items removed when queued offline', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeTaskItem({
            id: 'item-1',
            completedAt: '2026-01-05T10:00:00.000Z',
          }),
        ],
        { scope: Scope.workspace('test') }
      )
      const store = useTaskItemsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      await store.clearCompleted('list-1', ['item-1'])

      expect(pool.get('taskItem', 'item-1')).toBeUndefined()
    })

    it('does not restore items that were already absent from the pool', async () => {
      const pool = useObjectPoolStore()
      // item-absent was never in the pool (maybe already removed by WS)
      const store = useTaskItemsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      // Should not crash even when items are not in the pool
      await expect(
        store.clearCompleted('list-1', ['item-absent'])
      ).rejects.toThrow('Server error')

      expect(pool.getAll('taskItem')).toHaveLength(0)
    })
  })

  describe('$reset', () => {
    it('clears loading and error state', async () => {
      const store = useTaskItemsStore()

      enqueueImpl = async () => {
        throw new Error('fail')
      }
      try {
        await store.addItem('list-1', 'x')
      } catch {
        // expected
      }

      expect(store.error).toBe('Failed to add item')

      store.$reset()

      expect(store.loading).toBe(false)
      expect(store.error).toBeNull()
    })
  })
})
