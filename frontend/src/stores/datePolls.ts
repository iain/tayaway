import { ref } from 'vue'
import { defineStore } from 'pinia'
import { api } from '@/api/client'
import type { PoolApiResponse } from '@/types/pool'

export const useDatePollsStore = defineStore('datePolls', () => {
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function createPoll(eventId: string, deadline: string): Promise<void> {
    loading.value = true
    error.value = null
    try {
      await api.post<PoolApiResponse>(`/events/${eventId}/poll`, { deadline })
    } catch (e) {
      error.value = 'Failed to create poll'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function closePoll(
    eventId: string,
    selectedDateRangeId: string
  ): Promise<void> {
    loading.value = true
    error.value = null
    try {
      await api.post<PoolApiResponse>(`/events/${eventId}/poll/close`, {
        selected_date_range_id: selectedDateRangeId,
      })
    } catch (e) {
      error.value = 'Failed to close poll'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function reopenPoll(eventId: string, deadline: string): Promise<void> {
    loading.value = true
    error.value = null
    try {
      await api.post<PoolApiResponse>(`/events/${eventId}/poll/reopen`, {
        deadline,
      })
    } catch (e) {
      error.value = 'Failed to reopen poll'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function addDateRange(
    eventId: string,
    startDate: string,
    endDate: string
  ): Promise<void> {
    loading.value = true
    error.value = null
    try {
      await api.post<PoolApiResponse>(`/events/${eventId}/poll/date-ranges`, {
        start_date: startDate,
        end_date: endDate,
      })
    } catch (e) {
      error.value = 'Failed to add date range'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function removeDateRange(
    eventId: string,
    dateRangeId: string
  ): Promise<void> {
    loading.value = true
    error.value = null
    try {
      await api.delete<PoolApiResponse>(
        `/events/${eventId}/poll/date-ranges/${dateRangeId}`
      )
    } catch (e) {
      error.value = 'Failed to remove date range'
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
    createPoll,
    closePoll,
    reopenPoll,
    addDateRange,
    removeDateRange,
    $reset,
  }
})
