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
  // Every read and write below takes the workspace it applies to. The
  // directory works off the active one, but settings administers any
  // workspace you own — including ones no client is subscribed to.
  function activeWorkspaceId(): string | null {
    return useWorkspaceStore().currentWorkspaceId
  }

  // Members are derived directly from the pool — no cross-referencing needed
  function membersIn(workspaceId: string | null): PoolMember[] {
    const pool = useObjectPoolStore()

    return pool
      .getAll('member')
      .filter((m) => m.workspaceId === workspaceId)
      .sort((a, b) => {
        const nameA = a.name || a.email
        const nameB = b.name || b.email
        return nameA.localeCompare(nameB)
      })
  }

  // Pending invites derived from pool, filtered to workspace + non-accepted
  function pendingInvitesIn(workspaceId: string | null): PoolWorkspaceInvite[] {
    const pool = useObjectPoolStore()

    return pool
      .getAll('workspaceInvite')
      .filter((i) => i.workspaceId === workspaceId && !i.acceptedAt)
      .sort(
        (a, b) =>
          new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()
      )
  }

  const members = computed((): PoolMember[] => membersIn(activeWorkspaceId()))

  const pendingInvites = computed((): PoolWorkspaceInvite[] =>
    pendingInvitesIn(activeWorkspaceId())
  )

  // The workspace channel already carries the roster for the workspace a
  // client is subscribed to; this fills in the ones it isn't.
  async function fetchMembers(workspaceId = activeWorkspaceId()) {
    if (!workspaceId) return

    try {
      await api.get(`/members?workspace_id=${workspaceId}`)
    } catch (err) {
      console.warn('Failed to fetch members', err)
    }
  }

  async function fetchInvites(workspaceId = activeWorkspaceId()) {
    if (!workspaceId) return

    try {
      await api.get(`/invites?workspace_id=${workspaceId}`)
    } catch (err) {
      if ((err as { status?: number }).status === 403) {
        // Silently fail — user may not be admin
        return
      }
      console.warn('Failed to fetch invites', err)
    }
  }

  async function createInvite(
    email: string,
    name?: string,
    workspaceId = activeWorkspaceId()
  ) {
    const { mutate } = useMutation()
    await mutate('Failed to send invite', (commandQueue) =>
      commandQueue.enqueue('POST', '/invites', {
        email,
        name,
        workspace_id: workspaceId,
      })
    )
  }

  async function cancelInvite(id: string, workspaceId = activeWorkspaceId()) {
    const { destroy } = useMutation()
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

  async function sendReminder(id: string, workspaceId = activeWorkspaceId()) {
    const { mutate } = useMutation()
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
    membersIn,
    pendingInvitesIn,
    fetchMembers,
    fetchInvites,
    createInvite,
    cancelInvite,
    sendReminder,
    updateMemberRole,
    $reset,
  }
})
