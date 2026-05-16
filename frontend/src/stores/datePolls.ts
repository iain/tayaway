import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useObjectPoolStore } from './objectPool'
import { useCommandQueueStore, CommandQueuedError } from './commandQueue'
import { currentWorkspaceScopeOrThrow } from '@/api/poolScope'
import type { PoolApiResponse, PoolDateRange } from '@/types/pool'

export const useDatePollsStore = defineStore('datePolls', () => {
  const { loading, error, mutate, update } = useMutation()

  async function createPoll(eventId: string, deadline: string) {
    await mutate('Failed to create poll', (commandQueue) =>
      commandQueue.enqueue<PoolApiResponse>('POST', `/events/${eventId}/poll`, {
        deadline,
      })
    )
  }

  async function closePoll(eventId: string, selectedDateRangeId: string) {
    const pool = useObjectPoolStore()
    const poll = pool.getAll('datePoll').find((dp) => dp.eventId === eventId)
    if (!poll) throw new Error('Poll not found')

    await update(
      'Failed to close poll',
      'datePoll',
      poll.id,
      {
        status: 'resolved',
        selectedDateRangeId,
        closedAt: new Date().toISOString(),
      },
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'POST',
          `/events/${eventId}/poll/close`,
          {
            selected_date_range_id: selectedDateRangeId,
          }
        )
    )
  }

  async function reopenPoll(eventId: string, deadline: string) {
    const pool = useObjectPoolStore()
    const poll = pool.getAll('datePoll').find((dp) => dp.eventId === eventId)
    if (!poll) throw new Error('Poll not found')

    await update(
      'Failed to reopen poll',
      'datePoll',
      poll.id,
      { status: 'open', selectedDateRangeId: null, closedAt: null, deadline },
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'POST',
          `/events/${eventId}/poll/reopen`,
          {
            deadline,
          }
        )
    )
  }

  async function addDateRange(
    eventId: string,
    startDate: string,
    endDate: string
  ) {
    const pool = useObjectPoolStore()
    const commandQueue = useCommandQueueStore()

    const poll = pool.getAll('datePoll').find((dp) => dp.eventId === eventId)
    if (!poll) throw new Error('Poll not found')

    const dateRangeId = crypto.randomUUID()
    const now = new Date().toISOString()
    const tempDateRange: PoolDateRange = {
      id: dateRangeId,
      objectType: 'dateRange',
      datePollId: poll.id,
      startDate,
      endDate,
      updatedAt: now,
    }

    // Multi-object optimistic: add dateRange + update poll's dateRangeIds
    pool.set(currentWorkspaceScopeOrThrow(), tempDateRange, { isTemp: true })
    const pendingId = pool.addPending('datePoll', poll.id, {
      dateRangeIds: [...poll.dateRangeIds, dateRangeId],
    })

    loading.value = true
    error.value = null
    try {
      await commandQueue.enqueue<PoolApiResponse>(
        'POST',
        `/events/${eventId}/poll/date-ranges`,
        { id: dateRangeId, start_date: startDate, end_date: endDate }
      )
    } catch (e) {
      if (e instanceof CommandQueuedError) {
        return
      }
      // Rollback both
      pool.remove('dateRange', dateRangeId)
      pool.removePending(pendingId)
      error.value = 'Failed to add date range'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function removeDateRange(eventId: string, dateRangeId: string) {
    const pool = useObjectPoolStore()
    const commandQueue = useCommandQueueStore()

    const poll = pool.getAll('datePoll').find((dp) => dp.eventId === eventId)
    if (!poll) throw new Error('Poll not found')

    // Save for rollback (including the scopes it was in)
    const savedDateRange = pool.getServer('dateRange', dateRangeId)
    const savedScopes = pool.scopesOf(dateRangeId)

    // Multi-object optimistic: remove dateRange + update poll's dateRangeIds
    pool.remove('dateRange', dateRangeId)
    const pendingId = pool.addPending('datePoll', poll.id, {
      dateRangeIds: poll.dateRangeIds.filter((id) => id !== dateRangeId),
    })

    loading.value = true
    error.value = null
    try {
      await commandQueue.enqueue<PoolApiResponse>(
        'DELETE',
        `/events/${eventId}/poll/date-ranges/${dateRangeId}`
      )
    } catch (e) {
      if (e instanceof CommandQueuedError) {
        return
      }
      // Rollback both — restore to every scope the dateRange was in.
      if (savedDateRange) {
        for (const scope of savedScopes) {
          pool.set(scope, savedDateRange)
        }
      }
      pool.removePending(pendingId)
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
