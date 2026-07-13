import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useObjectPoolStore } from './objectPool'
import { useCommandQueueStore, CommandQueuedError } from './commandQueue'
import { useAuthStore } from './auth'
import { positionBetween } from '@/utils/position'
import type { PoolApiResponse, PoolTaskItem } from '@/types/pool'

export const useTaskItemsStore = defineStore('taskItems', () => {
  const { loading, error, create, update, destroy } = useMutation()

  async function addItem(taskListId: string, content: string) {
    const itemId = crypto.randomUUID()
    const now = new Date().toISOString()
    const tempItem: PoolTaskItem = {
      id: itemId,
      objectType: 'taskItem',
      taskListId,
      userId: useAuthStore().currentUserId ?? null,
      content,
      completedAt: null,
      position: Date.now(), // temporary; server assigns real position
      createdAt: now,
      updatedAt: now,
    }

    const result = await create(
      'Failed to add item',
      tempItem,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'POST',
          `/task-lists/${taskListId}/items`,
          {
            content,
            id: itemId,
          }
        )
    )
    return { itemId, queued: result.queued }
  }

  async function updateItem(
    taskListId: string,
    itemId: string,
    changes: { content?: string; completed?: boolean }
  ) {
    const poolChanges: Partial<PoolTaskItem> = {}
    if (changes.content !== undefined) {
      poolChanges.content = changes.content
    }
    if (changes.completed !== undefined) {
      poolChanges.completedAt = changes.completed
        ? new Date().toISOString()
        : null
    }

    await update(
      'Failed to update item',
      'taskItem',
      itemId,
      poolChanges,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'PUT',
          `/task-lists/${taskListId}/items/${itemId}`,
          changes
        )
    )
  }

  async function repositionItem(
    sourceListId: string,
    itemId: string,
    beforePosition: number | null,
    afterPosition: number | null,
    targetListId?: string
  ) {
    const newPosition = positionBetween(beforePosition, afterPosition)
    const poolChanges: Partial<PoolTaskItem> = { position: newPosition }
    if (targetListId && targetListId !== sourceListId) {
      poolChanges.taskListId = targetListId
    }

    await update(
      'Failed to reposition item',
      'taskItem',
      itemId,
      poolChanges,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'PUT',
          `/task-lists/${sourceListId}/items/${itemId}`,
          {
            position: newPosition,
            ...(targetListId && targetListId !== sourceListId
              ? { task_list_id: targetListId }
              : {}),
          }
        )
    )
  }

  async function deleteItem(taskListId: string, itemId: string) {
    await destroy('Failed to delete item', 'taskItem', itemId, (commandQueue) =>
      commandQueue.enqueue(
        'DELETE',
        `/task-lists/${taskListId}/items/${itemId}`
      )
    )
  }

  async function clearCompleted(
    taskListId: string,
    completedItemIds: string[]
  ) {
    const pool = useObjectPoolStore()
    // Snapshot each item with its scope set so a rollback restores it to
    // the same delivery channels.
    const saved = completedItemIds.flatMap((id) => {
      const item = pool.getServer('taskItem', id)
      return item ? [{ object: item, scopes: pool.scopesOf(id) }] : []
    })

    // Optimistic: remove completed items from pool (single reactivity trigger)
    pool.removeMany('taskItem', completedItemIds)

    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      await commandQueue.enqueue(
        'POST',
        `/task-lists/${taskListId}/clear-completed`,
        {},
        { kind: 'destroy', removed: saved }
      )
    } catch (e) {
      if (e instanceof CommandQueuedError) {
        // Request queued for later — keep items optimistically removed
        return
      }
      pool.restore(saved)
      error.value = 'Failed to clear completed items'
      throw e
    } finally {
      loading.value = false
    }
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return {
    loading,
    error,
    addItem,
    updateItem,
    repositionItem,
    deleteItem,
    clearCompleted,
    $reset,
  }
})
