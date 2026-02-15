import { computed } from 'vue'
import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useObjectPoolStore } from './objectPool'
import { useWorkspaceStore } from './workspace'
import type { CreateUserRequest, CreateUserResponse } from '@/types'
import type { PoolApiResponse, PoolUser } from '@/types/pool'

interface CreateUserResponseWithPool extends CreateUserResponse {
  objects?: PoolApiResponse['objects']
}

export const useUsersStore = defineStore('users', () => {
  const { loading, error, mutate } = useMutation()

  // Users are derived from the pool, enriched with their workspace role
  const users = computed((): (PoolUser & { role: string | null })[] => {
    const pool = useObjectPoolStore()
    const workspaceStore = useWorkspaceStore()
    const workspace = workspaceStore.currentWorkspace

    // Build a userId → role map from workspace memberships
    const roleByUserId = new Map<string, string>()
    if (workspace) {
      const memberships = pool.getMany(
        'workspaceMembership',
        workspace.membershipIds
      )
      for (const m of memberships) {
        roleByUserId.set(m.userId, m.role)
      }
    }

    return pool
      .getAll('user')
      .map((user) => ({ ...user, role: roleByUserId.get(user.id) ?? null }))
      .sort((a, b) => {
        const nameA = a.name || a.email
        const nameB = b.name || b.email
        return nameA.localeCompare(nameB)
      })
  })

  async function createUser(data: CreateUserRequest) {
    const result = await mutate('Failed to create user', (commandQueue) =>
      commandQueue.enqueue<CreateUserResponseWithPool>('POST', '/users', {
        ...data,
        workspace_id: useWorkspaceStore().currentWorkspaceId,
      })
    )
    return { queued: result.queued }
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return {
    users,
    loading,
    error,
    createUser,
    $reset,
  }
})
