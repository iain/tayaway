import { computed } from 'vue'
import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useObjectPoolStore } from './objectPool'
import { useWorkspaceStore } from './workspace'
import type { CreateMemberRequest, CreateMemberResponse } from '@/types'
import type { PoolApiResponse, PoolMember } from '@/types/pool'

interface UpdateRoleResponse {
  objects?: PoolApiResponse['objects']
}

interface CreateMemberResponseWithPool extends CreateMemberResponse {
  objects?: PoolApiResponse['objects']
}

export const useMembersStore = defineStore('members', () => {
  const { loading, error, create } = useMutation()

  // Members are derived directly from the pool — no cross-referencing needed
  const members = computed((): PoolMember[] => {
    const pool = useObjectPoolStore()
    const workspaceStore = useWorkspaceStore()
    const workspaceId = workspaceStore.currentWorkspaceId

    return pool
      .getAll('member')
      .filter((m) => m.workspaceId === workspaceId)
      .sort((a, b) => {
        const nameA = a.name || a.email
        const nameB = b.name || b.email
        return nameA.localeCompare(nameB)
      })
  })

  async function createMember(data: CreateMemberRequest) {
    const membershipId = crypto.randomUUID()
    const workspaceId = useWorkspaceStore().currentWorkspaceId!
    const now = new Date().toISOString()
    const tempMember: PoolMember = {
      id: membershipId,
      objectType: 'member',
      workspaceId,
      email: data.email,
      name: data.name ?? null,
      role: 'member',
      createdAt: now,
      updatedAt: now,
    }

    const result = await create(
      'Failed to add member',
      tempMember,
      (commandQueue) =>
        commandQueue.enqueue<CreateMemberResponseWithPool>('POST', '/members', {
          ...data,
          id: membershipId,
          workspace_id: workspaceId,
        })
    )
    return { queued: result.queued }
  }

  async function updateMemberRole(memberId: string, role: string) {
    const { update } = useMutation()
    return await update(
      'Failed to update member role',
      'member',
      memberId,
      { role },
      (commandQueue) =>
        commandQueue.enqueue<UpdateRoleResponse>(
          'PUT',
          `/members/${memberId}`,
          { role }
        )
    )
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return {
    members,
    loading,
    error,
    createMember,
    updateMemberRole,
    $reset,
  }
})
