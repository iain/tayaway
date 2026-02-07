import { ref } from 'vue'
import { defineStore } from 'pinia'
import { api } from '@/api/client'
import { useObjectPoolStore } from './objectPool'
import type { Vote, VoteResponse, VoteRequestBody, VoteApiResponse } from '@/types'
import type { PoolObject } from '@/types/pool'

// Extended response type that includes pool objects
interface VoteApiResponseWithPool extends VoteApiResponse {
  objects?: PoolObject[]
}

export const useVotesStore = defineStore('votes', () => {
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function submitVote(
    eventId: string,
    dateRangeId: string,
    response: VoteResponse,
    comment?: string
  ): Promise<Vote> {
    loading.value = true
    error.value = null
    try {
      const body: VoteRequestBody = {
        date_range_id: dateRangeId,
        response,
        comment,
      }
      const apiResponse = await api.post<VoteApiResponseWithPool>(`/events/${eventId}/votes`, body)

      // Import objects to pool if present
      if (apiResponse.data.objects) {
        const pool = useObjectPoolStore()
        pool.importObjects(apiResponse.data.objects)
      }

      return apiResponse.data.vote
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

      // Remove from pool
      const pool = useObjectPoolStore()
      pool.remove('vote', voteId)
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
