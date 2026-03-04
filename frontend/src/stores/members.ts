import { computed } from 'vue'
import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { api } from '@/api/client'
import { useObjectPoolStore } from './objectPool'
import { useWorkspaceStore } from './workspace'
import type {
  PoolApiResponse,
  PoolMember,
  PoolWorkspaceInvite,
} from '@/types/pool'

interface UpdateRoleResponse {
  objects?: PoolApiResponse['objects']
}

export const useMembersStore = defineStore('members', () => {
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

  // Pending invites derived from pool, filtered to current workspace + non-accepted
  const pendingInvites = computed((): PoolWorkspaceInvite[] => {
    const pool = useObjectPoolStore()
    const workspaceStore = useWorkspaceStore()
    const workspaceId = workspaceStore.currentWorkspaceId

    return pool
      .getAll('workspaceInvite')
      .filter((i) => i.workspaceId === workspaceId && !i.acceptedAt)
      .sort(
        (a, b) =>
          new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()
      )
  })

  async function fetchInvites() {
    const workspaceId = useWorkspaceStore().currentWorkspaceId
    if (!workspaceId) return

    try {
      await api.get(`/invites?workspace_id=${workspaceId}`)
    } catch {
      // Silently fail — user may not be admin
    }
  }

  async function createInvite(email: string, name?: string) {
    const { mutate } = useMutation()
    const workspaceId = useWorkspaceStore().currentWorkspaceId!
    await mutate('Failed to send invite', (commandQueue) =>
      commandQueue.enqueue('POST', '/invites', {
        email,
        name,
        workspace_id: workspaceId,
      })
    )
  }

  async function cancelInvite(id: string) {
    const { destroy } = useMutation()
    const workspaceId = useWorkspaceStore().currentWorkspaceId!
    await destroy(
      'Failed to cancel invite',
      'workspaceInvite',
      id,
      (commandQueue) =>
        commandQueue.enqueue(
          'DELETE',
          `/invites/${id}?workspace_id=${workspaceId}`
        )
    )
  }

  async function sendReminder(id: string) {
    const { mutate } = useMutation()
    const workspaceId = useWorkspaceStore().currentWorkspaceId!
    await mutate('Failed to send reminder', (commandQueue) =>
      commandQueue.enqueue(
        'POST',
        `/invites/${id}/remind?workspace_id=${workspaceId}`
      )
    )
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
    // All state is computed from pool — nothing to reset
  }

  return {
    members,
    pendingInvites,
    fetchInvites,
    createInvite,
    cancelInvite,
    sendReminder,
    updateMemberRole,
    $reset,
  }
})
