import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useObjectPoolStore } from './objectPool'
import { useCommandQueueStore } from './commandQueue'
import { useAuthStore } from './auth'
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
      memberId: useAuthStore().currentMemberId ?? null,
      content,
      completedAt: null,
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
    const saved = completedItemIds
      .map((id) => pool.getServer('taskItem', id))
      .filter(Boolean)

    // Optimistic: remove completed items from pool
    for (const id of completedItemIds) {
      pool.remove('taskItem', id)
    }

    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      await commandQueue.enqueue(
        'POST',
        `/task-lists/${taskListId}/clear-completed`,
        {}
      )
    } catch (e) {
      // Restore items on error
      for (const item of saved) {
        if (item) pool.set(item)
      }
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
    deleteItem,
    clearCompleted,
    $reset,
  }
})
