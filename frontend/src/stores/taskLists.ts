import { defineStore } from 'pinia'
import { nowIso } from '@/utils/date'
import { useMutation } from '@/composables/useMutation'
import { useAuthStore } from './auth'
import { useWorkspaceStore } from './workspace'
import { positionBetween } from '@/utils/position'
import type { PoolApiResponse, PoolTaskList } from '@/types/pool'

export const useTaskListsStore = defineStore('taskLists', () => {
  const { loading, error, create, update, destroy } = useMutation()

  async function createTaskList(name: string) {
    const listId = crypto.randomUUID()
    const now = nowIso()
    const workspaceId = useWorkspaceStore().currentWorkspaceId!
    const tempList: PoolTaskList = {
      id: listId,
      objectType: 'taskList',
      workspaceId,
      userId: useAuthStore().currentUserId ?? null,
      name,
      position: Date.now(), // temporary; server assigns real position
      createdAt: now,
      updatedAt: now,
    }

    const result = await create(
      'Failed to create task list',
      tempList,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>('POST', '/task-lists', {
          name,
          id: listId,
          workspace_id: workspaceId,
        })
    )
    return { listId, queued: result.queued }
  }

  async function updateTaskList(id: string, name: string) {
    await update(
      'Failed to update task list',
      'taskList',
      id,
      { name },
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>('PUT', `/task-lists/${id}`, {
          name,
        })
    )
  }

  async function repositionList(
    listId: string,
    beforePosition: number | null,
    afterPosition: number | null
  ) {
    const newPosition = positionBetween(beforePosition, afterPosition)
    await update(
      'Failed to reposition task list',
      'taskList',
      listId,
      { position: newPosition },
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>('PUT', `/task-lists/${listId}`, {
          position: newPosition,
        })
    )
  }

  async function deleteTaskList(id: string) {
    await destroy(
      'Failed to delete task list',
      'taskList',
      id,
      (commandQueue) => commandQueue.enqueue('DELETE', `/task-lists/${id}`)
    )
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return {
    loading,
    error,
    createTaskList,
    updateTaskList,
    repositionList,
    deleteTaskList,
    $reset,
  }
})
