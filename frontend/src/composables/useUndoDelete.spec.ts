import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useUndoDelete } from './useUndoDelete'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useNotificationsStore } from '@/stores/notifications'
import type { ObjectTypeMap } from '@/types/pool'

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

const enqueueMock = vi.fn()

vi.mock('@/stores/commandQueue', async () => {
  const actual = await vi.importActual<typeof import('@/stores/commandQueue')>(
    '@/stores/commandQueue'
  )
  return {
    ...actual,
    useCommandQueueStore: () => ({
      enqueue: enqueueMock,
    }),
  }
})

describe('useUndoDelete', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    setActivePinia(createPinia())
    enqueueMock.mockReset().mockResolvedValue({ data: {}, status: 200 })
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('removes the object from the pool immediately', () => {
    const pool = useObjectPoolStore()
    pool.set(makeTaskItem(), { scope: 'workspace:test' })
    expect(pool.get('taskItem', 'item-1')).toBeDefined()

    const { undoableDelete } = useUndoDelete()
    undoableDelete({
      objectType: 'taskItem',
      objectId: 'item-1',
      message: 'Item deleted',
      apiPath: '/task-lists/list-1/items/item-1',
    })

    expect(pool.get('taskItem', 'item-1')).toBeUndefined()
  })

  it('shows a toast with Undo action', () => {
    const pool = useObjectPoolStore()
    pool.set(makeTaskItem(), { scope: 'workspace:test' })

    const { undoableDelete } = useUndoDelete()
    undoableDelete({
      objectType: 'taskItem',
      objectId: 'item-1',
      message: 'Item deleted',
      apiPath: '/task-lists/list-1/items/item-1',
    })

    const notifications = useNotificationsStore()
    expect(notifications.notifications).toHaveLength(1)
    expect(notifications.notifications[0]!.message).toBe('Item deleted')
    expect(notifications.notifications[0]!.actionLabel).toBe('Undo')
  })

  it('restores the object when Undo is clicked', () => {
    const pool = useObjectPoolStore()
    pool.set(makeTaskItem(), { scope: 'workspace:test' })

    const { undoableDelete } = useUndoDelete()
    undoableDelete({
      objectType: 'taskItem',
      objectId: 'item-1',
      message: 'Item deleted',
      apiPath: '/task-lists/list-1/items/item-1',
    })

    expect(pool.get('taskItem', 'item-1')).toBeUndefined()

    // Click undo
    const notifications = useNotificationsStore()
    notifications.notifications[0]!.action!()

    expect(pool.get('taskItem', 'item-1')).toBeDefined()
    expect(pool.get('taskItem', 'item-1')!.content).toBe('Buy groceries')
  })

  it('fires the API delete after the undo window expires', async () => {
    const pool = useObjectPoolStore()
    pool.set(makeTaskItem(), { scope: 'workspace:test' })

    const { undoableDelete } = useUndoDelete()
    undoableDelete({
      objectType: 'taskItem',
      objectId: 'item-1',
      message: 'Item deleted',
      apiPath: '/task-lists/list-1/items/item-1',
    })

    // API not called yet
    expect(enqueueMock).not.toHaveBeenCalled()

    // Advance past undo window
    await vi.advanceTimersByTimeAsync(5000)

    expect(enqueueMock).toHaveBeenCalledWith(
      'DELETE',
      '/task-lists/list-1/items/item-1'
    )
  })

  it('does not fire the API delete if Undo was clicked', async () => {
    const pool = useObjectPoolStore()
    pool.set(makeTaskItem(), { scope: 'workspace:test' })

    const { undoableDelete } = useUndoDelete()
    undoableDelete({
      objectType: 'taskItem',
      objectId: 'item-1',
      message: 'Item deleted',
      apiPath: '/task-lists/list-1/items/item-1',
    })

    // Click undo before timer expires
    const notifications = useNotificationsStore()
    notifications.notifications[0]!.action!()

    await vi.advanceTimersByTimeAsync(5000)

    expect(enqueueMock).not.toHaveBeenCalled()
  })

  it('restores objects if the API call fails', async () => {
    const pool = useObjectPoolStore()
    pool.set(makeTaskItem(), { scope: 'workspace:test' })

    enqueueMock.mockRejectedValueOnce(new Error('Server error'))

    const { undoableDelete } = useUndoDelete()
    undoableDelete({
      objectType: 'taskItem',
      objectId: 'item-1',
      message: 'Item deleted',
      apiPath: '/task-lists/list-1/items/item-1',
    })

    expect(pool.get('taskItem', 'item-1')).toBeUndefined()

    await vi.advanceTimersByTimeAsync(5000)

    // Object restored after API failure
    expect(pool.get('taskItem', 'item-1')).toBeDefined()

    // Error toast shown
    const notifications = useNotificationsStore()
    const errorToast = notifications.notifications.find(
      (n) => n.type === 'error'
    )
    expect(errorToast).toBeDefined()
  })
})
