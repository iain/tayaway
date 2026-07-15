import { defineStore } from 'pinia'
import { nowIso } from '@/utils/date'
import { useMutation } from '@/composables/useMutation'
import { useObjectPoolStore } from './objectPool'
import { useCommandQueueStore, CommandQueuedError } from './commandQueue'
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
        closedAt: nowIso(),
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
    const now = nowIso()
    const tempDateRange: PoolDateRange = {
      id: dateRangeId,
      objectType: 'dateRange',
      datePollId: poll.id,
      startDate,
      endDate,
      updatedAt: now,
    }

    // Multi-object optimistic: add dateRange + update poll's dateRangeIds.
    // dateRange has no workspaceId field; the pool falls back to the active
    // workspace's scope.
    pool.set(tempDateRange, { isTemp: true })
    const pendingId = pool.addPending('datePoll', poll.id, {
      dateRangeIds: [...poll.dateRangeIds, dateRangeId],
    })

    loading.value = true
    error.value = null
    try {
      await commandQueue.enqueue<PoolApiResponse>(
        'POST',
        `/events/${eventId}/poll/date-ranges`,
        { id: dateRangeId, start_date: startDate, end_date: endDate },
        // Composite rollback: a permanently-failed replay must undo both
        // optimistic pool mutations, mirroring the error path below.
        [
          { kind: 'create', objectType: 'dateRange', objectId: dateRangeId },
          {
            kind: 'update',
            objectType: 'datePoll',
            objectId: poll.id,
            pendingId,
          },
        ]
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

    // Snapshot for rollback. cascadeRemove returns the entries with their
    // prior scope sets attached, which pool.restore replays on failure.
    const removed = pool.cascadeRemove('dateRange', dateRangeId)
    const pendingId = pool.addPending('datePoll', poll.id, {
      dateRangeIds: poll.dateRangeIds.filter((id) => id !== dateRangeId),
    })

    loading.value = true
    error.value = null
    try {
      await commandQueue.enqueue<PoolApiResponse>(
        'DELETE',
        `/events/${eventId}/poll/date-ranges/${dateRangeId}`,
        undefined,
        [
          { kind: 'destroy', removed },
          {
            kind: 'update',
            objectType: 'datePoll',
            objectId: poll.id,
            pendingId,
          },
        ]
      )
    } catch (e) {
      if (e instanceof CommandQueuedError) {
        return
      }
      pool.restore(removed)
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
