import { ref } from 'vue'
import { defineStore } from 'pinia'
import { useCommandQueueStore, CommandQueuedError } from './commandQueue'
import type { PoolApiResponse } from '@/types/pool'

export const useDatePollsStore = defineStore('datePolls', () => {
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function createPoll(eventId: string, deadline: string): Promise<void> {
    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      await commandQueue.enqueue<PoolApiResponse>(
        'POST',
        `/events/${eventId}/poll`,
        { deadline }
      )
    } catch (e) {
      if (e instanceof CommandQueuedError) return
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
      const commandQueue = useCommandQueueStore()
      await commandQueue.enqueue<PoolApiResponse>(
        'POST',
        `/events/${eventId}/poll/close`,
        { selected_date_range_id: selectedDateRangeId }
      )
    } catch (e) {
      if (e instanceof CommandQueuedError) return
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
      const commandQueue = useCommandQueueStore()
      await commandQueue.enqueue<PoolApiResponse>(
        'POST',
        `/events/${eventId}/poll/reopen`,
        { deadline }
      )
    } catch (e) {
      if (e instanceof CommandQueuedError) return
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
      const commandQueue = useCommandQueueStore()
      const dateRangeId = crypto.randomUUID()
      await commandQueue.enqueue<PoolApiResponse>(
        'POST',
        `/events/${eventId}/poll/date-ranges`,
        { id: dateRangeId, start_date: startDate, end_date: endDate }
      )
    } catch (e) {
      if (e instanceof CommandQueuedError) return
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
      const commandQueue = useCommandQueueStore()
      await commandQueue.enqueue<PoolApiResponse>(
        'DELETE',
        `/events/${eventId}/poll/date-ranges/${dateRangeId}`
      )
    } catch (e) {
      if (e instanceof CommandQueuedError) return
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
