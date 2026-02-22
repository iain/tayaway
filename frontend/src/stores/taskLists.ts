import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useAuthStore } from './auth'
import { useWorkspaceStore } from './workspace'
import type { PoolApiResponse, PoolTaskList } from '@/types/pool'

export const useTaskListsStore = defineStore('taskLists', () => {
  const { loading, error, create, update, destroy } = useMutation()

  async function createTaskList(name: string) {
    const listId = crypto.randomUUID()
    const now = new Date().toISOString()
    const workspaceId = useWorkspaceStore().currentWorkspaceId!
    const tempList: PoolTaskList = {
      id: listId,
      objectType: 'taskList',
      workspaceId,
      memberId: useAuthStore().currentMemberId ?? null,
      name,
      itemIds: [],
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
    deleteTaskList,
    $reset,
  }
})
