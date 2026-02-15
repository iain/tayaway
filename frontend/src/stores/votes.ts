import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useAuthStore } from './auth'
import { useObjectPoolStore } from './objectPool'
import type { VoteResponse, VoteRequestBody } from '@/types'
import type { PoolApiResponse, PoolVote } from '@/types/pool'

export const useVotesStore = defineStore('votes', () => {
  const { loading, error, create, update, destroy } = useMutation()

  async function submitVote(
    eventId: string,
    dateRangeId: string,
    response: VoteResponse,
    comment?: string
  ) {
    const pool = useObjectPoolStore()
    const userId = useAuthStore().user!.id
    const body: VoteRequestBody = {
      date_range_id: dateRangeId,
      response,
      comment,
    }

    // Check for existing vote by this user on this date range
    const existingVote = pool
      .getAll('vote')
      .find((v) => v.dateRangeId === dateRangeId && v.userId === userId)

    if (existingVote) {
      const result = await update(
        'Failed to submit vote',
        'vote',
        existingVote.id,
        { response, comment: comment ?? null },
        (commandQueue) =>
          commandQueue.enqueue<PoolApiResponse>(
            'POST',
            `/events/${eventId}/votes`,
            body
          )
      )
      return { voteId: existingVote.id, queued: result.queued }
    } else {
      const voteId = crypto.randomUUID()
      const now = new Date().toISOString()
      const tempVote: PoolVote = {
        id: voteId,
        objectType: 'vote',
        dateRangeId,
        userId,
        response,
        comment: comment ?? null,
        createdAt: now,
        updatedAt: now,
      }
      const result = await create(
        'Failed to submit vote',
        tempVote,
        (commandQueue) =>
          commandQueue.enqueue<PoolApiResponse>(
            'POST',
            `/events/${eventId}/votes`,
            {
              ...body,
              id: voteId,
            }
          )
      )
      return { voteId, queued: result.queued }
    }
  }

  async function deleteVote(eventId: string, voteId: string) {
    await destroy('Failed to delete vote', 'vote', voteId, (commandQueue) =>
      commandQueue.enqueue('DELETE', `/events/${eventId}/votes/${voteId}`)
    )
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return {
    loading,
    error,
    submitVote,
    deleteVote,
    $reset,
  }
})
