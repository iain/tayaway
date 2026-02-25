import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { api } from '@/api/client'
import { useObjectPoolStore } from './objectPool'
import { useWorkspaceStore } from './workspace'
import type { InviteResponse, InvitesListResponse } from '@/types'
import type { PoolApiResponse, PoolMember } from '@/types/pool'

interface UpdateRoleResponse {
  objects?: PoolApiResponse['objects']
}

export const useMembersStore = defineStore('members', () => {
  const pendingInvites = ref<InviteResponse[]>([])
  const invitesLoading = ref(false)

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

  async function fetchInvites() {
    const workspaceId = useWorkspaceStore().currentWorkspaceId
    if (!workspaceId) return

    invitesLoading.value = true
    try {
      const { data } = await api.get<InvitesListResponse>(
        `/invites?workspace_id=${workspaceId}`
      )
      pendingInvites.value = data.invites
    } catch {
      // Silently fail — user may not be admin
      pendingInvites.value = []
    } finally {
      invitesLoading.value = false
    }
  }

  async function createInvite(email: string) {
    const workspaceId = useWorkspaceStore().currentWorkspaceId!
    await api.post<InviteResponse>('/invites', {
      email,
      workspace_id: workspaceId,
    })
    await fetchInvites()
  }

  async function cancelInvite(id: string) {
    const workspaceId = useWorkspaceStore().currentWorkspaceId!
    await api.delete(`/invites/${id}?workspace_id=${workspaceId}`)
    pendingInvites.value = pendingInvites.value.filter((i) => i.id !== id)
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
    pendingInvites.value = []
    invitesLoading.value = false
  }

  return {
    members,
    pendingInvites,
    invitesLoading,
    fetchInvites,
    createInvite,
    cancelInvite,
    updateMemberRole,
    $reset,
  }
})
