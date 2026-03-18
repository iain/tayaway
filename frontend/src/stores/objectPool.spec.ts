import { describe, it, expect, beforeEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from './objectPool'
import type { ObjectTypeMap } from '@/types/pool'

function makeEvent(
  overrides: Partial<ObjectTypeMap['event']> = {}
): ObjectTypeMap['event'] {
  return {
    id: 'evt-1',
    objectType: 'event',
    name: 'Test Event',
    description: null,
    startDate: null,
    endDate: null,
    locationName: null,
    latitude: null,
    longitude: null,
    workspaceId: 'ws-1',
    userId: 'user-1',
    datePollId: null,
    rsvpIds: [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function makeTaskItem(
  overrides: Partial<ObjectTypeMap['taskItem']> = {}
): ObjectTypeMap['taskItem'] {
  return {
    id: 'item-1',
    objectType: 'taskItem',
    taskListId: 'list-1',
    userId: null,
    content: 'Do something',
    completedAt: null,
    position: 1,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

describe('objectPool store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  describe('importObjects', () => {
    it('imports a new object into the pool', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent()

      pool.importObjects([event])

      expect(pool.get('event', 'evt-1')).toEqual(event)
    })

    it('updates an existing object when newer', () => {
      const pool = useObjectPoolStore()
      const old = makeEvent({ updatedAt: '2026-01-01T00:00:00.000Z' })
      const newer = makeEvent({
        updatedAt: '2026-01-02T00:00:00.000Z',
        name: 'Updated',
      })

      pool.importObjects([old])
      pool.importObjects([newer])

      expect(pool.get('event', 'evt-1')?.name).toBe('Updated')
    })

    it('ignores an older object', () => {
      const pool = useObjectPoolStore()
      const newer = makeEvent({
        updatedAt: '2026-01-02T00:00:00.000Z',
        name: 'Newer',
      })
      const older = makeEvent({
        updatedAt: '2026-01-01T00:00:00.000Z',
        name: 'Older',
      })

      pool.importObjects([newer])
      pool.importObjects([older])

      expect(pool.get('event', 'evt-1')?.name).toBe('Newer')
    })

    it('imports multiple objects of different types', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent()
      const item = makeTaskItem()

      pool.importObjects([event, item])

      expect(pool.get('event', 'evt-1')).toEqual(event)
      expect(pool.get('taskItem', 'item-1')).toEqual(item)
    })

    it('clears pending updates when server object is newer', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ updatedAt: '2026-01-01T00:00:00.000Z' })
      pool.importObjects([event])

      pool.addPending('event', 'evt-1', { name: 'Optimistic' })
      expect(pool.hasPending('event', 'evt-1')).toBe(true)

      // Import a server object newer than the pending update
      const serverUpdate = makeEvent({
        updatedAt: '2099-01-01T00:00:00.000Z',
        name: 'Server',
      })
      pool.importObjects([serverUpdate])

      expect(pool.hasPending('event', 'evt-1')).toBe(false)
      expect(pool.get('event', 'evt-1')?.name).toBe('Server')
    })

    it('preserves pending updates when they are newer than server object', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ updatedAt: '2026-01-01T00:00:00.000Z' })
      pool.importObjects([event])

      // Add pending — its timestamp will be Date.now() which is newer than 2026-01-02
      pool.addPending('event', 'evt-1', { name: 'Optimistic' })

      // Import server object that is newer than original but older than pending
      const serverUpdate = makeEvent({
        updatedAt: '2026-01-02T00:00:00.000Z',
        name: 'Server',
      })
      pool.importObjects([serverUpdate])

      // Pending should still be there since Date.now() > 2026-01-02 timestamp
      expect(pool.hasPending('event', 'evt-1')).toBe(true)
      expect(pool.get('event', 'evt-1')?.name).toBe('Optimistic')
    })
  })

  describe('get with pending overlay', () => {
    it('returns server data when no pending updates', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ name: 'Original' })
      pool.importObjects([event])

      expect(pool.get('event', 'evt-1')?.name).toBe('Original')
    })

    it('merges pending updates over server data', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ name: 'Original', description: 'desc' })
      pool.importObjects([event])

      pool.addPending('event', 'evt-1', { name: 'Pending Name' })

      const result = pool.get('event', 'evt-1')
      expect(result?.name).toBe('Pending Name')
      expect(result?.description).toBe('desc') // unchanged field preserved
    })

    it('merges multiple pending updates in order', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ name: 'Original' })
      pool.importObjects([event])

      pool.addPending('event', 'evt-1', { name: 'First' })
      pool.addPending('event', 'evt-1', { name: 'Second' })

      expect(pool.get('event', 'evt-1')?.name).toBe('Second')
    })

    it('returns undefined for nonexistent objects', () => {
      const pool = useObjectPoolStore()
      expect(pool.get('event', 'nonexistent')).toBeUndefined()
    })
  })

  describe('addPending / removePending lifecycle', () => {
    it('addPending returns a unique pendingId', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent()
      pool.importObjects([event])

      const id1 = pool.addPending('event', 'evt-1', { name: 'A' })
      const id2 = pool.addPending('event', 'evt-1', { name: 'B' })

      expect(id1).not.toBe(id2)
    })

    it('removePending rolls back a specific pending update', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ name: 'Original' })
      pool.importObjects([event])

      const pendingId = pool.addPending('event', 'evt-1', {
        name: 'Optimistic',
      })
      expect(pool.get('event', 'evt-1')?.name).toBe('Optimistic')

      pool.removePending(pendingId)
      expect(pool.get('event', 'evt-1')?.name).toBe('Original')
      expect(pool.hasPending('event', 'evt-1')).toBe(false)
    })

    it('removePending only removes the targeted update', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ name: 'Original' })
      pool.importObjects([event])

      const id1 = pool.addPending('event', 'evt-1', { name: 'First' })
      pool.addPending('event', 'evt-1', { description: 'Added desc' })

      pool.removePending(id1)

      const result = pool.get('event', 'evt-1')
      expect(result?.name).toBe('Original') // rolled back
      expect(result?.description).toBe('Added desc') // still pending
      expect(pool.hasPending('event', 'evt-1')).toBe(true)
    })

    it('hasPending returns false when no pending updates exist', () => {
      const pool = useObjectPoolStore()
      expect(pool.hasPending('event', 'evt-1')).toBe(false)
    })
  })

  describe('set', () => {
    it('inserts a new object directly', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent()

      pool.set(event)

      expect(pool.get('event', 'evt-1')).toEqual(event)
    })

    it('overwrites an existing object', () => {
      const pool = useObjectPoolStore()
      pool.set(makeEvent({ name: 'First' }))
      pool.set(makeEvent({ name: 'Second' }))

      expect(pool.get('event', 'evt-1')?.name).toBe('Second')
    })
  })

  describe('remove', () => {
    it('removes an object from the pool', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()])

      pool.remove('event', 'evt-1')

      expect(pool.get('event', 'evt-1')).toBeUndefined()
    })

    it('clears pending updates for the removed object', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()])
      pool.addPending('event', 'evt-1', { name: 'Pending' })

      pool.remove('event', 'evt-1')

      expect(pool.hasPending('event', 'evt-1')).toBe(false)
    })
  })

  describe('getAll', () => {
    it('returns all objects of a type', () => {
      const pool = useObjectPoolStore()
      const e1 = makeEvent({ id: 'evt-1' })
      const e2 = makeEvent({ id: 'evt-2', name: 'Second' })
      pool.importObjects([e1, e2])

      const all = pool.getAll('event')
      expect(all).toHaveLength(2)
    })

    it('returns objects with pending updates merged', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Original' })])
      pool.addPending('event', 'evt-1', { name: 'Pending' })

      const all = pool.getAll('event')
      expect(all).toHaveLength(1)
      expect(all[0]!.name).toBe('Pending')
    })

    it('returns empty array for type with no objects', () => {
      const pool = useObjectPoolStore()
      expect(pool.getAll('event')).toEqual([])
    })

    it('returns the same array reference when nothing has changed (cache hit)', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ id: 'evt-1' })])

      const first = pool.getAll('event')
      const second = pool.getAll('event')

      expect(second).toBe(first)
    })

    it('returns a new array reference after an import (cache miss)', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ id: 'evt-1' })])

      const first = pool.getAll('event')

      pool.importObjects([makeEvent({ id: 'evt-2', name: 'Second' })])
      const second = pool.getAll('event')

      expect(second).not.toBe(first)
      expect(second).toHaveLength(2)
    })

    it('returns a new array reference after remove (cache miss)', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ id: 'evt-1' })])

      const first = pool.getAll('event')
      pool.remove('event', 'evt-1')
      const second = pool.getAll('event')

      expect(second).not.toBe(first)
      expect(second).toHaveLength(0)
    })

    it('returns a new array reference after addPending (cache miss)', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ id: 'evt-1', name: 'Original' })])

      const first = pool.getAll('event')
      pool.addPending('event', 'evt-1', { name: 'Pending' })
      const second = pool.getAll('event')

      expect(second).not.toBe(first)
      expect(second[0]!.name).toBe('Pending')
    })

    it('does not invalidate cache for an unrelated type mutation', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ id: 'evt-1' }), makeTaskItem()])

      const eventsBefore = pool.getAll('event')

      // mutate taskItem type only
      pool.remove('taskItem', 'item-1')

      const eventsAfter = pool.getAll('event')
      expect(eventsAfter).toBe(eventsBefore)
    })
  })

  describe('getMany', () => {
    it('returns objects matching the given IDs', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ id: 'evt-1' }),
        makeEvent({ id: 'evt-2' }),
        makeEvent({ id: 'evt-3' }),
      ])

      const result = pool.getMany('event', ['evt-1', 'evt-3'])
      expect(result).toHaveLength(2)
      expect(result.map((e) => e.id)).toEqual(['evt-1', 'evt-3'])
    })

    it('skips nonexistent IDs', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ id: 'evt-1' })])

      const result = pool.getMany('event', ['evt-1', 'missing'])
      expect(result).toHaveLength(1)
    })
  })

  describe('findBy', () => {
    it('finds an object by a field value', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ id: 'evt-1', userId: 'user-a' }),
        makeEvent({ id: 'evt-2', userId: 'user-b' }),
      ])

      const found = pool.findBy('event', 'userId', 'user-b')
      expect(found?.id).toBe('evt-2')
    })

    it('returns undefined when no match', () => {
      const pool = useObjectPoolStore()
      expect(pool.findBy('event', 'userId', 'nope')).toBeUndefined()
    })
  })

  describe('getServer', () => {
    it('returns raw server data without pending overlay', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Server Name' })])
      pool.addPending('event', 'evt-1', { name: 'Pending' })

      const server = pool.getServer('event', 'evt-1')
      expect(server?.name).toBe('Server Name')
    })

    it('returns undefined for nonexistent objects', () => {
      const pool = useObjectPoolStore()
      expect(pool.getServer('event', 'nope')).toBeUndefined()
    })
  })

  describe('replaceObjects', () => {
    it('replaces all pool data with the given objects', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ id: 'evt-1' }),
        makeEvent({ id: 'evt-2' }),
      ])

      pool.replaceObjects([makeEvent({ id: 'evt-3', name: 'New' })])

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(pool.get('event', 'evt-2')).toBeUndefined()
      expect(pool.get('event', 'evt-3')?.name).toBe('New')
    })

    it('clears pending updates older than server data', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()])
      pool.addPending('event', 'evt-1', { name: 'Pending' })

      // Replace with a server object whose updatedAt is in the future,
      // so the pending update (created at Date.now()) is older
      const futureDate = new Date(Date.now() + 60_000).toISOString()
      pool.replaceObjects([makeEvent({ updatedAt: futureDate })])

      expect(pool.hasPending('event', 'evt-1')).toBe(false)
    })

    it('preserves pending updates newer than server data', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()])
      pool.addPending('event', 'evt-1', { name: 'Pending' })

      // Replace with server data that has an old updatedAt
      pool.replaceObjects([makeEvent()])

      // Pending update was created at Date.now() which is after 2026-01-01,
      // so it should be preserved
      expect(pool.hasPending('event', 'evt-1')).toBe(true)
    })
  })

  describe('clearExcept', () => {
    it('clears all types except the specified ones', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent(), makeTaskItem()])

      pool.clearExcept('event')

      expect(pool.get('event', 'evt-1')).toBeDefined()
      expect(pool.get('taskItem', 'item-1')).toBeUndefined()
    })

    it('clears pending updates for cleared types', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent(), makeTaskItem()])
      pool.addPending('event', 'evt-1', { name: 'A' })
      pool.addPending('taskItem', 'item-1', { content: 'B' })

      pool.clearExcept('event')

      expect(pool.hasPending('event', 'evt-1')).toBe(true)
      expect(pool.hasPending('taskItem', 'item-1')).toBe(false)
    })
  })

  describe('restorePendingUpdates', () => {
    it('restores cached pending updates', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Server' })])

      const cached = new Map([
        [
          'event:evt-1',
          [
            {
              id: 'p1',
              objectType: 'event' as const,
              objectId: 'evt-1',
              changes: { name: 'Cached Pending' },
              timestamp: Date.now(),
            },
          ],
        ],
      ])
      pool.restorePendingUpdates(cached)

      expect(pool.hasPending('event', 'evt-1')).toBe(true)
      expect(pool.get('event', 'evt-1')?.name).toBe('Cached Pending')
    })

    it('does nothing with empty map', () => {
      const pool = useObjectPoolStore()
      const versionBefore = pool.version

      pool.restorePendingUpdates(new Map())

      expect(pool.version).toBe(versionBefore)
    })
  })

  describe('$reset', () => {
    it('clears all objects and pending updates', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()])
      pool.addPending('event', 'evt-1', { name: 'Pending' })

      pool.$reset()

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(pool.hasPending('event', 'evt-1')).toBe(false)
    })
  })

  describe('cascadeRemove', () => {
    function makeDatePoll(
      overrides: Partial<ObjectTypeMap['datePoll']> = {}
    ): ObjectTypeMap['datePoll'] {
      return {
        id: 'poll-1',
        objectType: 'datePoll',
        eventId: 'evt-1',
        deadline: '2026-06-01T00:00:00.000Z',
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
        startDate: '2026-06-10',
        endDate: '2026-06-12',
        voteIds: [],
        updatedAt: '2026-01-01T00:00:00.000Z',
        ...overrides,
      }
    }

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

    it('removes the object itself', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('event', 'evt-1')).toBeUndefined()
    })

    it('removes deeply nested children in a single pass', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent(),
        makeDatePoll(),
        makeDateRange(),
        makeVote(),
        makeVote({ id: 'vote-2' }),
      ])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(pool.get('datePoll', 'poll-1')).toBeUndefined()
      expect(pool.get('dateRange', 'dr-1')).toBeUndefined()
      expect(pool.get('vote', 'vote-1')).toBeUndefined()
      expect(pool.get('vote', 'vote-2')).toBeUndefined()
    })

    it('only removes children belonging to the deleted parent', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ id: 'evt-1' }),
        makeEvent({ id: 'evt-2' }),
        makeDatePoll({ id: 'poll-1', eventId: 'evt-1' }),
        makeDatePoll({ id: 'poll-2', eventId: 'evt-2' }),
      ])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('datePoll', 'poll-1')).toBeUndefined()
      expect(pool.get('datePoll', 'poll-2')).toBeDefined()
      expect(pool.get('event', 'evt-2')).toBeDefined()
    })

    it('bumps the version exactly once per affected type regardless of child count', () => {
      const pool = useObjectPoolStore()
      // 1 event → 1 datePoll → 3 dateRanges → 2 votes each = 8 total objects
      pool.importObjects([
        makeEvent(),
        makeDatePoll(),
        makeDateRange({ id: 'dr-1', datePollId: 'poll-1' }),
        makeDateRange({ id: 'dr-2', datePollId: 'poll-1' }),
        makeDateRange({ id: 'dr-3', datePollId: 'poll-1' }),
        makeVote({ id: 'vote-1', dateRangeId: 'dr-1' }),
        makeVote({ id: 'vote-2', dateRangeId: 'dr-1' }),
        makeVote({ id: 'vote-3', dateRangeId: 'dr-2' }),
        makeVote({ id: 'vote-4', dateRangeId: 'dr-2' }),
      ])

      const versionBefore = pool.version
      const pollVersionBefore = pool.typeVersions.get('datePoll')!
      const dateRangeVersionBefore = pool.typeVersions.get('dateRange')!
      const voteVersionBefore = pool.typeVersions.get('vote')!

      pool.cascadeRemove('event', 'evt-1')

      // Global version should increment by exactly 1 (one bumpVersion call)
      expect(pool.version).toBe(versionBefore + 1)
      // Each affected type version should also only increment by 1
      expect(pool.typeVersions.get('datePoll')).toBe(pollVersionBefore + 1)
      expect(pool.typeVersions.get('dateRange')).toBe(dateRangeVersionBefore + 1)
      expect(pool.typeVersions.get('vote')).toBe(voteVersionBefore + 1)
    })

    it('clears pending updates for removed objects', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent(), makeDatePoll()])
      pool.addPending('datePoll', 'poll-1', {
        deadline: '2099-01-01T00:00:00.000Z',
      })

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.hasPending('datePoll', 'poll-1')).toBe(false)
    })

    it('returns all removed objects for rollback', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent(), makeDatePoll(), makeDateRange()])

      const removed = pool.cascadeRemove('event', 'evt-1')

      expect(removed).toHaveLength(3)
      const ids = removed.map((o) => o.id)
      expect(ids).toContain('evt-1')
      expect(ids).toContain('poll-1')
      expect(ids).toContain('dr-1')
    })

    it('handles cascading a nonexistent object without throwing', () => {
      const pool = useObjectPoolStore()

      expect(() => pool.cascadeRemove('event', 'nonexistent')).not.toThrow()
    })
  })
})
