import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useVotesStore } from './votes'
import { useObjectPoolStore } from './objectPool'
import { CommandQueuedError } from '@/stores/commandQueue'
import type { ObjectTypeMap } from '@/types/pool'
import type { ApiResponse } from '@/api/client'

function makeVote(
  overrides: Partial<ObjectTypeMap['vote']> = {}
): ObjectTypeMap['vote'] {
  return {
    id: 'vote-1',
    objectType: 'vote',
    dateRangeId: 'dr-1',
    userId: 'user-1',
    response: 'yes',
    comment: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function okResponse<T>(data: T): ApiResponse<T> {
  return { data, status: 200 }
}

// Mutable handler so individual tests can swap out behaviour.
let enqueueImpl: () => Promise<ApiResponse<unknown>> = async () =>
  okResponse({})

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

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({ currentUserId: 'user-1' }),
}))

describe('votes store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    enqueueImpl = async () => okResponse({})
  })

  describe('submitVote — new vote', () => {
    it('creates a temp vote in the pool optimistically', async () => {
      const pool = useObjectPoolStore()
      const store = useVotesStore()

      let voteDuringCall: ObjectTypeMap['vote'] | undefined
      enqueueImpl = async () => {
        const votes = pool.getAll('vote')
        voteDuringCall = votes[0]
        return okResponse({})
      }

      const result = await store.submitVote('evt-1', 'dr-1', 'yes', 'Nice!')

      expect(voteDuringCall).toBeDefined()
      expect(voteDuringCall!.dateRangeId).toBe('dr-1')
      expect(voteDuringCall!.userId).toBe('user-1')
      expect(voteDuringCall!.response).toBe('yes')
      expect(voteDuringCall!.comment).toBe('Nice!')
      expect(result.queued).toBe(false)
    })

    it('returns a voteId matching the temp object', async () => {
      const pool = useObjectPoolStore()
      const store = useVotesStore()

      const result = await store.submitVote('evt-1', 'dr-1', 'no')

      expect(result.voteId).toBeDefined()
      expect(pool.get('vote', result.voteId)).toBeDefined()
    })

    it('sets comment to null when not provided', async () => {
      const pool = useObjectPoolStore()
      const store = useVotesStore()

      let voteDuringCall: ObjectTypeMap['vote'] | undefined
      enqueueImpl = async () => {
        voteDuringCall = pool.getAll('vote')[0]
        return okResponse({})
      }

      await store.submitVote('evt-1', 'dr-1', 'yes')

      expect(voteDuringCall!.comment).toBeNull()
    })

    it('keeps temp vote in pool when request is queued offline', async () => {
      const pool = useObjectPoolStore()
      const store = useVotesStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      const result = await store.submitVote('evt-1', 'dr-1', 'yes')

      expect(result.queued).toBe(true)
      expect(pool.get('vote', result.voteId)).toBeDefined()
    })

    it('removes temp vote from pool on server error', async () => {
      const pool = useObjectPoolStore()
      const store = useVotesStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(async () => {
        await store.submitVote('evt-1', 'dr-1', 'yes')
      }).rejects.toThrow('Server error')

      // All votes should be gone (temp was rolled back)
      expect(pool.getAll('vote')).toHaveLength(0)
      expect(store.error).toBe('Failed to submit vote')
    })
  })

  describe('submitVote — existing vote (update)', () => {
    it('optimistically updates the existing vote response', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeVote({ response: 'yes' })])
      const store = useVotesStore()

      let responseDuringCall: string | undefined
      enqueueImpl = async () => {
        responseDuringCall = pool.get('vote', 'vote-1')?.response
        return okResponse({})
      }

      const result = await store.submitVote('evt-1', 'dr-1', 'no')

      expect(responseDuringCall).toBe('no')
      expect(result.voteId).toBe('vote-1')
      expect(result.queued).toBe(false)
    })

    it('optimistically updates the comment', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeVote({ comment: null })])
      const store = useVotesStore()

      let commentDuringCall: string | null | undefined
      enqueueImpl = async () => {
        commentDuringCall = pool.get('vote', 'vote-1')?.comment
        return okResponse({})
      }

      await store.submitVote('evt-1', 'dr-1', 'yes', 'Updated comment')

      expect(commentDuringCall).toBe('Updated comment')
    })

    it('sets comment to null when not provided on update', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeVote({ comment: 'old' })])
      const store = useVotesStore()

      let commentDuringCall: string | null | undefined
      enqueueImpl = async () => {
        commentDuringCall = pool.get('vote', 'vote-1')?.comment
        return okResponse({})
      }

      await store.submitVote('evt-1', 'dr-1', 'yes')

      expect(commentDuringCall).toBeNull()
    })

    it('keeps pending update when queued offline', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeVote({ response: 'yes' })])
      const store = useVotesStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      const result = await store.submitVote('evt-1', 'dr-1', 'no')

      expect(result.queued).toBe(true)
      expect(pool.get('vote', 'vote-1')?.response).toBe('no')
      expect(pool.hasPending('vote', 'vote-1')).toBe(true)
    })

    it('rolls back pending update on server error', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeVote({ response: 'yes' })])
      const store = useVotesStore()

      enqueueImpl = async () => {
        throw new Error('Validation error')
      }

      await expect(
        store.submitVote('evt-1', 'dr-1', 'no')
      ).rejects.toThrow('Validation error')

      expect(pool.get('vote', 'vote-1')?.response).toBe('yes')
      expect(pool.hasPending('vote', 'vote-1')).toBe(false)
    })
  })

  describe('deleteVote', () => {
    it('optimistically removes the vote from the pool', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeVote()])
      const store = useVotesStore()

      let presentDuringCall: boolean | undefined
      enqueueImpl = async () => {
        presentDuringCall = pool.get('vote', 'vote-1') !== undefined
        return okResponse({})
      }

      await store.deleteVote('evt-1', 'vote-1')

      expect(presentDuringCall).toBe(false)
      expect(pool.get('vote', 'vote-1')).toBeUndefined()
    })

    it('restores the vote when the API call fails', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeVote()])
      const store = useVotesStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(store.deleteVote('evt-1', 'vote-1')).rejects.toThrow(
        'Server error'
      )

      expect(pool.get('vote', 'vote-1')).toBeDefined()
      expect(store.error).toBe('Failed to delete vote')
    })

    it('keeps the vote removed when queued offline', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeVote()])
      const store = useVotesStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      await store.deleteVote('evt-1', 'vote-1')

      expect(pool.get('vote', 'vote-1')).toBeUndefined()
    })
  })

  describe('$reset', () => {
    it('clears loading and error state', async () => {
      const store = useVotesStore()

      // Trigger an error to set state
      enqueueImpl = async () => {
        throw new Error('fail')
      }
      try {
        await store.submitVote('evt-1', 'dr-1', 'yes')
      } catch {
        // expected
      }

      expect(store.error).toBe('Failed to submit vote')

      store.$reset()

      expect(store.loading).toBe(false)
      expect(store.error).toBeNull()
    })
  })
})
