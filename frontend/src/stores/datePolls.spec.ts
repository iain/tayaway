import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useDatePollsStore } from './datePolls'
import { useObjectPoolStore } from './objectPool'
import { useWorkspaceStore } from './workspace'
import { CommandQueuedError } from '@/stores/commandQueue'
import type { ObjectTypeMap } from '@/types/pool'
import type { ApiResponse } from '@/api/client'

function makeDatePoll(
  overrides: Partial<ObjectTypeMap['datePoll']> = {}
): ObjectTypeMap['datePoll'] {
  return {
    id: 'poll-1',
    objectType: 'datePoll',
    eventId: 'evt-1',
    deadline: '2026-02-01T00:00:00.000Z',
    selectedDateRangeId: null,
    closedAt: null,
    status: 'open',
    dateRangeIds: [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function makeDateRange(
  overrides: Partial<ObjectTypeMap['dateRange']> = {}
): ObjectTypeMap['dateRange'] {
  return {
    id: 'dr-1',
    objectType: 'dateRange',
    datePollId: 'poll-1',
    startDate: '2026-03-01',
    endDate: '2026-03-05',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function okResponse<T>(data: T): ApiResponse<T> {
  return { data, status: 200 }
}

let enqueueImpl: () => Promise<ApiResponse<unknown>> = async () =>
  okResponse({ objects: [] })

vi.mock('@/stores/commandQueue', async () => {
  const actual = await vi.importActual<typeof import('@/stores/commandQueue')>(
    '@/stores/commandQueue'
  )
  return {
    ...actual,
    useCommandQueueStore: () => ({
      enqueue: vi.fn().mockImplementation(() => enqueueImpl()),
    }),
  }
})

describe('datePolls store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    // addDateRange (and the error-path rollback in removeDateRange) tag the
    // optimistic dateRange with the active workspace's scope; production code
    // throws if none is set, so the tests need a workspace too.
    localStorage.setItem('current_workspace_id', 'ws-test')
    useWorkspaceStore().initialize(['ws-test'])
    enqueueImpl = async () => okResponse({ objects: [] })
  })

  describe('closePoll', () => {
    it('optimistically updates the poll status to resolved', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeDatePoll({ status: 'open' })], {
        scope: Scope.workspace('test'),
      })
      const store = useDatePollsStore()

      let statusDuringCall: string | undefined
      enqueueImpl = async () => {
        statusDuringCall = pool.get('datePoll', 'poll-1')?.status
        return okResponse({ objects: [] })
      }

      await store.closePoll('evt-1', 'dr-1')

      expect(statusDuringCall).toBe('resolved')
    })

    it('optimistically sets the selectedDateRangeId', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeDatePoll({ selectedDateRangeId: null })], {
        scope: Scope.workspace('test'),
      })
      const store = useDatePollsStore()

      let selectedDuringCall: string | null | undefined
      enqueueImpl = async () => {
        selectedDuringCall = pool.get('datePoll', 'poll-1')?.selectedDateRangeId
        return okResponse({ objects: [] })
      }

      await store.closePoll('evt-1', 'dr-2')

      expect(selectedDuringCall).toBe('dr-2')
    })

    it('throws when poll not found', async () => {
      const store = useDatePollsStore()

      await expect(store.closePoll('evt-1', 'dr-1')).rejects.toThrow(
        'Poll not found'
      )
    })

    it('rolls back the optimistic update on server error', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [makeDatePoll({ status: 'open', selectedDateRangeId: null })],
        { scope: Scope.workspace('test') }
      )
      const store = useDatePollsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(store.closePoll('evt-1', 'dr-1')).rejects.toThrow()

      expect(pool.get('datePoll', 'poll-1')?.status).toBe('open')
      expect(pool.get('datePoll', 'poll-1')?.selectedDateRangeId).toBeNull()
    })
  })

  describe('reopenPoll', () => {
    it('optimistically updates the poll status back to open', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeDatePoll({
            status: 'resolved',
            selectedDateRangeId: 'dr-1',
            closedAt: '2026-01-15T00:00:00.000Z',
          }),
        ],
        { scope: Scope.workspace('test') }
      )
      const store = useDatePollsStore()

      let statusDuringCall: string | undefined
      enqueueImpl = async () => {
        statusDuringCall = pool.get('datePoll', 'poll-1')?.status
        return okResponse({ objects: [] })
      }

      await store.reopenPoll('evt-1', '2026-03-01T00:00:00.000Z')

      expect(statusDuringCall).toBe('open')
    })

    it('clears selectedDateRangeId and closedAt on reopen', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeDatePoll({
            status: 'resolved',
            selectedDateRangeId: 'dr-1',
            closedAt: '2026-01-15T00:00:00.000Z',
          }),
        ],
        { scope: Scope.workspace('test') }
      )
      const store = useDatePollsStore()

      let pollDuringCall: ObjectTypeMap['datePoll'] | undefined
      enqueueImpl = async () => {
        pollDuringCall = pool.get('datePoll', 'poll-1')
        return okResponse({ objects: [] })
      }

      await store.reopenPoll('evt-1', '2026-03-01T00:00:00.000Z')

      expect(pollDuringCall!.selectedDateRangeId).toBeNull()
      expect(pollDuringCall!.closedAt).toBeNull()
    })

    it('throws when poll not found', async () => {
      const store = useDatePollsStore()

      await expect(
        store.reopenPoll('evt-1', '2026-03-01T00:00:00.000Z')
      ).rejects.toThrow('Poll not found')
    })
  })

  describe('addDateRange', () => {
    it('inserts a temp date range and updates poll.dateRangeIds optimistically', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeDatePoll({ dateRangeIds: [] })], {
        scope: Scope.workspace('test'),
      })
      const store = useDatePollsStore()

      let dateRangesDuringCall: ObjectTypeMap['dateRange'][] | undefined
      let pollIdsDuringCall: string[] | undefined
      enqueueImpl = async () => {
        dateRangesDuringCall = pool.getAll('dateRange')
        pollIdsDuringCall = pool.get('datePoll', 'poll-1')?.dateRangeIds
        return okResponse({ objects: [] })
      }

      await store.addDateRange('evt-1', '2026-03-01', '2026-03-05')

      expect(dateRangesDuringCall).toHaveLength(1)
      expect(dateRangesDuringCall![0]!.startDate).toBe('2026-03-01')
      expect(dateRangesDuringCall![0]!.endDate).toBe('2026-03-05')
      expect(pollIdsDuringCall).toHaveLength(1)
    })

    it('rolls back both temp date range and poll pending update on server error', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeDatePoll({ dateRangeIds: [] })], {
        scope: Scope.workspace('test'),
      })
      const store = useDatePollsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(
        store.addDateRange('evt-1', '2026-03-01', '2026-03-05')
      ).rejects.toThrow('Server error')

      expect(pool.getAll('dateRange')).toHaveLength(0)
      expect(pool.get('datePoll', 'poll-1')?.dateRangeIds).toHaveLength(0)
      expect(pool.hasPending('datePoll', 'poll-1')).toBe(false)
      expect(store.error).toBe('Failed to add date range')
    })

    it('keeps the optimistic state when request is queued offline', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeDatePoll({ dateRangeIds: [] })], {
        scope: Scope.workspace('test'),
      })
      const store = useDatePollsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      await store.addDateRange('evt-1', '2026-03-01', '2026-03-05')

      expect(pool.getAll('dateRange')).toHaveLength(1)
      expect(pool.get('datePoll', 'poll-1')?.dateRangeIds).toHaveLength(1)
    })

    it('throws when poll not found', async () => {
      const store = useDatePollsStore()

      await expect(
        store.addDateRange('evt-1', '2026-03-01', '2026-03-05')
      ).rejects.toThrow('Poll not found')
    })
  })

  describe('removeDateRange', () => {
    it('removes the date range and updates poll.dateRangeIds optimistically', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [makeDatePoll({ dateRangeIds: ['dr-1'] }), makeDateRange()],
        { scope: Scope.workspace('test') }
      )
      const store = useDatePollsStore()

      let dateRangesDuringCall: ObjectTypeMap['dateRange'][] | undefined
      let pollIdsDuringCall: string[] | undefined
      enqueueImpl = async () => {
        dateRangesDuringCall = pool.getAll('dateRange')
        pollIdsDuringCall = pool.get('datePoll', 'poll-1')?.dateRangeIds
        return okResponse({ objects: [] })
      }

      await store.removeDateRange('evt-1', 'dr-1')

      expect(dateRangesDuringCall).toHaveLength(0)
      expect(pollIdsDuringCall).toHaveLength(0)
    })

    it('restores the date range and poll ids on server error', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [makeDatePoll({ dateRangeIds: ['dr-1'] }), makeDateRange()],
        { scope: Scope.workspace('test') }
      )
      const store = useDatePollsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(store.removeDateRange('evt-1', 'dr-1')).rejects.toThrow(
        'Server error'
      )

      expect(pool.get('dateRange', 'dr-1')).toBeDefined()
      expect(pool.get('datePoll', 'poll-1')?.dateRangeIds).toContain('dr-1')
      expect(pool.hasPending('datePoll', 'poll-1')).toBe(false)
      expect(store.error).toBe('Failed to remove date range')
    })

    it('keeps the optimistic removal when request is queued offline', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [makeDatePoll({ dateRangeIds: ['dr-1'] }), makeDateRange()],
        { scope: Scope.workspace('test') }
      )
      const store = useDatePollsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      await store.removeDateRange('evt-1', 'dr-1')

      expect(pool.get('dateRange', 'dr-1')).toBeUndefined()
      expect(pool.get('datePoll', 'poll-1')?.dateRangeIds).not.toContain('dr-1')
    })

    it('throws when poll not found', async () => {
      const store = useDatePollsStore()

      await expect(store.removeDateRange('evt-1', 'dr-1')).rejects.toThrow(
        'Poll not found'
      )
    })
  })

  describe('$reset', () => {
    it('clears loading and error state', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeDatePoll()], { scope: Scope.workspace('test') })
      const store = useDatePollsStore()

      enqueueImpl = async () => {
        throw new Error('fail')
      }
      try {
        await store.addDateRange('evt-1', '2026-03-01', '2026-03-05')
      } catch {
        // expected
      }

      expect(store.error).toBe('Failed to add date range')

      store.$reset()

      expect(store.loading).toBe(false)
      expect(store.error).toBeNull()
    })
  })
})
