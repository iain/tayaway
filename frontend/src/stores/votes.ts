import { ref } from 'vue'
import { defineStore } from 'pinia'
import { api } from '@/api/client'
import type { VoteResponse, VoteRequestBody } from '@/types'
import type { PoolApiResponse } from '@/types/pool'

export const useVotesStore = defineStore('votes', () => {
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function submitVote(
    eventId: string,
    dateRangeId: string,
    response: VoteResponse,
    comment?: string
  ): Promise<string> {
    loading.value = true
    error.value = null
    try {
      const body: VoteRequestBody = {
        date_range_id: dateRangeId,
        response,
        comment,
      }
      const apiResponse = await api.post<PoolApiResponse>(`/events/${eventId}/votes`, body)
      const vote = apiResponse.data.objects.find(o => o.objectType === 'vote')
      if (!vote) throw new Error('No vote in response')
      return vote.id
    } catch (e) {
      error.value = 'Failed to submit vote'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function deleteVote(eventId: string, voteId: string): Promise<void> {
    loading.value = true
    error.value = null
    try {
      await api.delete(`/events/${eventId}/votes/${voteId}`)
    } catch (e) {
      error.value = 'Failed to delete vote'
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
    submitVote,
    deleteVote,
    $reset,
  }
})
