import { ref } from 'vue'
import { api } from '@/api/client'
import type { Vote, VoteResponse, VoteRequestBody, VoteApiResponse } from '@/types'

const loading = ref(false)
const error = ref<string | null>(null)

export function useVotes() {
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
      const apiResponse = await api.post<VoteApiResponse>(`/events/${eventId}/votes`, body)
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
    } catch (e) {
      error.value = 'Failed to delete vote'
      throw e
    } finally {
      loading.value = false
    }
  }

  return {
    loading,
    error,
    submitVote,
    deleteVote,
  }
}
