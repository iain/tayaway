import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import type { PoolApiResponse } from '@/types/pool'

/**
 * Standalone guest commands (doc/attendances.md): rename and delete stay
 * separate from the attendance upsert — they never race a create because
 * the UI only offers them for guests that already exist in the pool.
 */
export const useGuestsStore = defineStore('guests', () => {
  const { loading, error, update, destroy } = useMutation()

  /** Renaming also clears the placeholder flag server-side: a
   *  backfill-synthesized "Guest 1 (host)" becomes a real, picker-visible
   *  person the moment somebody names them. */
  async function renameGuest(
    workspaceId: string,
    guestId: string,
    name: string
  ) {
    await update(
      'Failed to rename guest',
      'guest',
      guestId,
      { name, placeholder: false },
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'PUT',
          `/workspaces/${workspaceId}/guests/${guestId}`,
          { name }
        )
    )
  }

  /** Allowed only while no attendance rows reference the guest — the server
   *  answers 403 (has_attendances) otherwise. */
  async function deleteGuest(workspaceId: string, guestId: string) {
    await destroy('Failed to delete guest', 'guest', guestId, (commandQueue) =>
      commandQueue.enqueue(
        'DELETE',
        `/workspaces/${workspaceId}/guests/${guestId}`
      )
    )
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return { loading, error, renameGuest, deleteGuest, $reset }
})
