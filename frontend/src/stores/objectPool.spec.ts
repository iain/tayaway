import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { watchEffect } from 'vue'
import { useObjectPoolStore } from './objectPool'
import {
  makeEvent,
  makeTaskItem,
  makeDatePoll,
  makeDateRange,
  makeVote,
  makeRsvp,
  makeExpense,
  makeExpenseParticipant,
  makeSettlement,
  makeSettlementTransfer,
  makeChoreRoster,
  makeChore,
  makeChoreAssignment,
  makeTaskList,
  makeMember,
  makeWorkspace,
} from '@/test/factories'

describe('objectPool store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  describe('importObjects', () => {
    it('imports a new object into the pool', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent()

      pool.importObjects('workspace:test', [event])

      expect(pool.get('event', 'evt-1')).toEqual(event)
    })

    it('updates an existing object when newer', () => {
      const pool = useObjectPoolStore()
      const old = makeEvent({ updatedAt: '2026-01-01T00:00:00.000Z' })
      const newer = makeEvent({
        updatedAt: '2026-01-02T00:00:00.000Z',
        name: 'Updated',
      })

      pool.importObjects('workspace:test', [old])
      pool.importObjects('workspace:test', [newer])

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

      pool.importObjects('workspace:test', [newer])
      pool.importObjects('workspace:test', [older])

      expect(pool.get('event', 'evt-1')?.name).toBe('Newer')
    })

    it('imports multiple objects of different types', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent()
      const item = makeTaskItem()

      pool.importObjects('workspace:test', [event, item])

      expect(pool.get('event', 'evt-1')).toEqual(event)
      expect(pool.get('taskItem', 'item-1')).toEqual(item)
    })

    it('clears pending updates when server object is newer', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ updatedAt: '2026-01-01T00:00:00.000Z' })
      pool.importObjects('workspace:test', [event])

      pool.addPending('event', 'evt-1', { name: 'Optimistic' })
      expect(pool.hasPending('event', 'evt-1')).toBe(true)

      // Import a server object newer than the pending update
      const serverUpdate = makeEvent({
        updatedAt: '2099-01-01T00:00:00.000Z',
        name: 'Server',
      })
      pool.importObjects('workspace:test', [serverUpdate])

      expect(pool.hasPending('event', 'evt-1')).toBe(false)
      expect(pool.get('event', 'evt-1')?.name).toBe('Server')
    })

    it('preserves pending updates when they are newer than server object', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ updatedAt: '2026-01-01T00:00:00.000Z' })
      pool.importObjects('workspace:test', [event])

      // Add pending — its timestamp will be Date.now() which is newer than 2026-01-02
      pool.addPending('event', 'evt-1', { name: 'Optimistic' })

      // Import server object that is newer than original but older than pending
      const serverUpdate = makeEvent({
        updatedAt: '2026-01-02T00:00:00.000Z',
        name: 'Server',
      })
      pool.importObjects('workspace:test', [serverUpdate])

      // Pending should still be there since Date.now() > 2026-01-02 timestamp
      expect(pool.hasPending('event', 'evt-1')).toBe(true)
      expect(pool.get('event', 'evt-1')?.name).toBe('Optimistic')
    })
  })

  describe('get with pending overlay', () => {
    it('returns server data when no pending updates', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ name: 'Original' })
      pool.importObjects('workspace:test', [event])

      expect(pool.get('event', 'evt-1')?.name).toBe('Original')
    })

    it('merges pending updates over server data', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ name: 'Original', description: 'desc' })
      pool.importObjects('workspace:test', [event])

      pool.addPending('event', 'evt-1', { name: 'Pending Name' })

      const result = pool.get('event', 'evt-1')
      expect(result?.name).toBe('Pending Name')
      expect(result?.description).toBe('desc') // unchanged field preserved
    })

    it('merges multiple pending updates in order', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ name: 'Original' })
      pool.importObjects('workspace:test', [event])

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
      pool.importObjects('workspace:test', [event])

      const id1 = pool.addPending('event', 'evt-1', { name: 'A' })
      const id2 = pool.addPending('event', 'evt-1', { name: 'B' })

      expect(id1).not.toBe(id2)
    })

    it('removePending rolls back a specific pending update', () => {
      const pool = useObjectPoolStore()
      const event = makeEvent({ name: 'Original' })
      pool.importObjects('workspace:test', [event])

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
      pool.importObjects('workspace:test', [event])

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

      pool.set('workspace:test', event)

      expect(pool.get('event', 'evt-1')).toEqual(event)
    })

    it('overwrites an existing object', () => {
      const pool = useObjectPoolStore()
      pool.set('workspace:test', makeEvent({ name: 'First' }))
      pool.set('workspace:test', makeEvent({ name: 'Second' }))

      expect(pool.get('event', 'evt-1')?.name).toBe('Second')
    })
  })

  describe('remove', () => {
    it('removes an object from the pool', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent()])

      pool.remove('event', 'evt-1')

      expect(pool.get('event', 'evt-1')).toBeUndefined()
    })

    it('clears pending updates for the removed object', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent()])
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
      pool.importObjects('workspace:test', [e1, e2])

      const all = pool.getAll('event')
      expect(all).toHaveLength(2)
    })

    it('returns objects with pending updates merged', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent({ name: 'Original' })])
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
      pool.importObjects('workspace:test', [makeEvent({ id: 'evt-1' })])

      const first = pool.getAll('event')
      const second = pool.getAll('event')

      expect(second).toBe(first)
    })

    it('returns a new array reference after an import (cache miss)', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent({ id: 'evt-1' })])

      const first = pool.getAll('event')

      pool.importObjects('workspace:test', [makeEvent({ id: 'evt-2', name: 'Second' })])
      const second = pool.getAll('event')

      expect(second).not.toBe(first)
      expect(second).toHaveLength(2)
    })

    it('returns a new array reference after remove (cache miss)', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent({ id: 'evt-1' })])

      const first = pool.getAll('event')
      pool.remove('event', 'evt-1')
      const second = pool.getAll('event')

      expect(second).not.toBe(first)
      expect(second).toHaveLength(0)
    })

    it('returns a new array reference after addPending (cache miss)', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent({ id: 'evt-1', name: 'Original' })])

      const first = pool.getAll('event')
      pool.addPending('event', 'evt-1', { name: 'Pending' })
      const second = pool.getAll('event')

      expect(second).not.toBe(first)
      expect(second[0]!.name).toBe('Pending')
    })

    it('does not invalidate cache for an unrelated type mutation', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent({ id: 'evt-1' }), makeTaskItem()])

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
      pool.importObjects('workspace:test', [
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
      pool.importObjects('workspace:test', [makeEvent({ id: 'evt-1' })])

      const result = pool.getMany('event', ['evt-1', 'missing'])
      expect(result).toHaveLength(1)
    })
  })

  describe('findBy', () => {
    it('finds an object by a field value', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
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
      pool.importObjects('workspace:test', [makeEvent({ name: 'Server Name' })])
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
      pool.importObjects('workspace:test', [
        makeEvent({ id: 'evt-1' }),
        makeEvent({ id: 'evt-2' }),
      ])

      pool.replaceScope('workspace:test', [makeEvent({ id: 'evt-3', name: 'New' })])

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(pool.get('event', 'evt-2')).toBeUndefined()
      expect(pool.get('event', 'evt-3')?.name).toBe('New')
    })

    it('clears pending updates older than server data', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent()])
      pool.addPending('event', 'evt-1', { name: 'Pending' })

      // Replace with a server object whose updatedAt is in the future,
      // so the pending update (created at Date.now()) is older
      const futureDate = new Date(Date.now() + 60_000).toISOString()
      pool.replaceScope('workspace:test', [makeEvent({ updatedAt: futureDate })])

      expect(pool.hasPending('event', 'evt-1')).toBe(false)
    })

    it('preserves pending updates newer than server data', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent()])
      pool.addPending('event', 'evt-1', { name: 'Pending' })

      // Replace with server data that has an old updatedAt
      pool.replaceScope('workspace:test', [makeEvent()])

      // Pending update was created at Date.now() which is after 2026-01-01,
      // so it should be preserved
      expect(pool.hasPending('event', 'evt-1')).toBe(true)
    })

    it('preserves temp objects absent from server payload (queued create)', () => {
      const pool = useObjectPoolStore()
      // Simulate an optimistic create: object inserted directly via set(),
      // no server confirmation yet (create command still in queue)
      const tempEvent = makeEvent({ id: 'temp-1', name: 'Temp Event' })
      pool.set('workspace:test', tempEvent, { isTemp: true })

      // Full sync arrives — server does not know about temp-1 yet
      const serverEvent = makeEvent({ id: 'evt-2', name: 'Server Event' })
      pool.replaceScope('workspace:test', [serverEvent])

      // Temp object must survive the sync so it stays visible in the UI
      expect(pool.get('event', 'temp-1')?.name).toBe('Temp Event')
      // Server object is present
      expect(pool.get('event', 'evt-2')?.name).toBe('Server Event')
    })

    it('removes server-imported objects that are absent from the server payload', () => {
      const pool = useObjectPoolStore()
      // Object confirmed by server (imported normally, not a temp)
      pool.importObjects('workspace:test', [makeEvent({ id: 'evt-old' })])

      // Full sync omits evt-old (deleted server-side)
      pool.replaceScope('workspace:test', [makeEvent({ id: 'evt-new', name: 'New' })])

      expect(pool.get('event', 'evt-old')).toBeUndefined()
      expect(pool.get('event', 'evt-new')?.name).toBe('New')
    })

    it('does not re-insert a temp object once the server confirms it', () => {
      const pool = useObjectPoolStore()
      const tempEvent = makeEvent({
        id: 'temp-1',
        name: 'Temp Event',
        updatedAt: '2026-01-01T00:00:00.000Z',
      })
      pool.set('workspace:test', tempEvent, { isTemp: true })

      // Server now includes it (create command was executed)
      const confirmedEvent = makeEvent({
        id: 'temp-1',
        name: 'Confirmed',
        updatedAt: '2026-01-02T00:00:00.000Z',
      })
      pool.replaceScope('workspace:test', [confirmedEvent])

      // Server version wins — temp is replaced, not duplicated or reverted
      expect(pool.get('event', 'temp-1')?.name).toBe('Confirmed')
    })

    it('does not preserve a temp object after cascadeRemove', () => {
      const pool = useObjectPoolStore()
      const tempEvent = makeEvent({ id: 'temp-1', name: 'Temp Event' })
      pool.set('workspace:test', tempEvent, { isTemp: true })

      // User cancels / error path removes the temp object
      pool.cascadeRemove('event', 'temp-1')

      // Full sync — temp-1 should not reappear
      pool.replaceScope('workspace:test', [makeEvent({ id: 'evt-2' })])
      expect(pool.get('event', 'temp-1')).toBeUndefined()
    })

    it('processes large payloads in chunks, resolving after all objects are inserted', async () => {
      vi.useFakeTimers()
      const pool = useObjectPoolStore()

      // Create 1200 events — exceeds the 200-object chunk size threshold
      const events = Array.from({ length: 1200 }, (_, i) =>
        makeEvent({ id: `evt-${i}`, name: `Event ${i}` })
      )

      const promise = pool.replaceScope('workspace:test', events)

      // Before timers run: the first chunk (0–199) is inserted synchronously
      // in the same call frame as the clear, so consumers never see an empty pool
      expect(pool.get('event', 'evt-0')?.name).toBe('Event 0')
      expect(pool.get('event', 'evt-199')?.name).toBe('Event 199')
      // Objects beyond the first chunk are not yet inserted
      expect(pool.get('event', 'evt-200')).toBeUndefined()

      // Run all pending timers (each remaining chunk schedules a setTimeout)
      await vi.runAllTimersAsync()
      await promise

      // All objects are inserted after all chunks complete
      expect(pool.get('event', 'evt-0')?.name).toBe('Event 0')
      expect(pool.get('event', 'evt-599')?.name).toBe('Event 599')
      expect(pool.get('event', 'evt-1199')?.name).toBe('Event 1199')

      vi.useRealTimers()
    })
  })

  describe('clearScope', () => {
    it('removes every object that lived only in the cleared scope', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:A', [makeEvent(), makeTaskItem()])

      pool.clearScope('workspace:A')

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(pool.get('taskItem', 'item-1')).toBeUndefined()
    })

    it('leaves objects in other scopes alone', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:A', [makeEvent({ id: 'evt-A' })])
      pool.importObjects('workspace:B', [makeEvent({ id: 'evt-B' })])

      pool.clearScope('workspace:A')

      expect(pool.get('event', 'evt-A')).toBeUndefined()
      expect(pool.get('event', 'evt-B')).toBeDefined()
    })

    it('keeps multi-scope objects when only one of their scopes is cleared', () => {
      const pool = useObjectPoolStore()
      const ownMember = makeMember({ userId: 'user-1' })
      // The user's own member row is delivered on both the workspace channel
      // (for the team view) and the personal channel (for cross-workspace
      // visibility), so it ends up tagged with both scopes.
      pool.importObjects('workspace:A', [ownMember])
      pool.importObjects('personal', [ownMember])

      pool.clearScope('workspace:A')

      expect(pool.get('member', ownMember.id)).toEqual(ownMember)
      expect(pool.scopesOf(ownMember.id)).toEqual(['personal'])
    })

    it('clears pending updates only when the underlying object is removed', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:A', [makeEvent()])
      pool.importObjects('workspace:B', [makeTaskItem()])
      pool.addPending('event', 'evt-1', { name: 'A' })
      pool.addPending('taskItem', 'item-1', { content: 'B' })

      pool.clearScope('workspace:A')

      // The event was only in workspace:A and is gone, so its pending update
      // dies with it. The taskItem lives in a different scope, untouched.
      expect(pool.hasPending('event', 'evt-1')).toBe(false)
      expect(pool.hasPending('taskItem', 'item-1')).toBe(true)
    })
  })

  describe('replaceScope', () => {
    it('replaces only the named scope; other scopes are untouched', async () => {
      const pool = useObjectPoolStore()
      const wsA = makeWorkspace({ id: 'ws-A', name: 'A' })
      const wsB = makeWorkspace({ id: 'ws-B', name: 'B' })
      pool.importObjects('personal', [wsA, wsB])

      // A workspace full-sync arrives for workspace:A's scope, carrying just
      // ws-A's data. The personal scope (which holds both workspace rows) is
      // not affected — both workspaces still appear in the pool.
      await pool.replaceScope('workspace:A', [makeEvent({ id: 'evt-1' })])

      expect(pool.get('workspace', 'ws-A')).toBeDefined()
      expect(pool.get('workspace', 'ws-B')).toBeDefined()
    })

    it('keeps multi-scope objects when only one of their scopes is replaced', async () => {
      const pool = useObjectPoolStore()
      const ownInA = makeMember({
        id: 'mem-a',
        workspaceId: 'ws-A',
        userId: 'user-1',
      })
      pool.importObjects('personal', [ownInA])
      pool.importObjects('workspace:A', [ownInA])

      // Replacing workspace:A with an empty payload removes the row from
      // workspace:A's scope but leaves it in `personal`.
      await pool.replaceScope('workspace:A', [])

      expect(pool.get('member', 'mem-a')).toBeDefined()
      expect(pool.scopesOf('mem-a')).toEqual(['personal'])
    })

    it('drops objects whose only scope is replaced and not re-listed', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:A', [
        makeEvent({ id: 'gone' }),
        makeEvent({ id: 'kept' }),
      ])

      await pool.replaceScope('workspace:A', [makeEvent({ id: 'kept' })])

      expect(pool.get('event', 'gone')).toBeUndefined()
      expect(pool.get('event', 'kept')).toBeDefined()
    })
  })

  describe('restorePendingUpdates', () => {
    it('restores cached pending updates', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent({ name: 'Server' })])

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
      const eventVersionBefore = pool.getVersion('event')

      pool.restorePendingUpdates(new Map())

      expect(pool.getVersion('event')).toBe(eventVersionBefore)
    })
  })

  describe('getVersion', () => {
    it('returns 0 for an untouched type', () => {
      const pool = useObjectPoolStore()
      expect(pool.getVersion('event')).toBe(0)
    })

    it('increments only the affected type when an object is imported', () => {
      const pool = useObjectPoolStore()
      const eventVersionBefore = pool.getVersion('event')
      const taskItemVersionBefore = pool.getVersion('taskItem')

      pool.importObjects('workspace:test', [makeEvent()])

      expect(pool.getVersion('event')).toBe(eventVersionBefore + 1)
      // Unrelated type must not be bumped
      expect(pool.getVersion('taskItem')).toBe(taskItemVersionBefore)
    })

    it('increments only the affected type when an object is set', () => {
      const pool = useObjectPoolStore()
      const taskItemVersionBefore = pool.getVersion('taskItem')

      pool.set('workspace:test', makeEvent())

      expect(pool.getVersion('taskItem')).toBe(taskItemVersionBefore)
    })

    it('increments only the affected type when an object is removed', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent()])
      const taskItemVersionBefore = pool.getVersion('taskItem')

      pool.remove('event', 'evt-1')

      expect(pool.getVersion('taskItem')).toBe(taskItemVersionBefore)
    })
  })

  describe('$reset', () => {
    it('clears all objects and pending updates', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent()])
      pool.addPending('event', 'evt-1', { name: 'Pending' })

      pool.$reset()

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(pool.hasPending('event', 'evt-1')).toBe(false)
    })
  })

  describe('cascadeRemove', () => {
    it('removes the object itself', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent()])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('event', 'evt-1')).toBeUndefined()
    })

    it('removes deeply nested children in a single pass', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
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
      pool.importObjects('workspace:test', [
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
      pool.importObjects('workspace:test', [
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

      const pollVersionBefore = pool.getVersion('datePoll')
      const dateRangeVersionBefore = pool.getVersion('dateRange')
      const voteVersionBefore = pool.getVersion('vote')
      // Types not involved should not change
      const taskItemVersionBefore = pool.getVersion('taskItem')

      pool.cascadeRemove('event', 'evt-1')

      // Each affected type version should increment by exactly 1 (one bumpVersion call)
      expect(pool.getVersion('datePoll')).toBe(pollVersionBefore + 1)
      expect(pool.getVersion('dateRange')).toBe(dateRangeVersionBefore + 1)
      expect(pool.getVersion('vote')).toBe(voteVersionBefore + 1)
      // Unaffected types must not be bumped
      expect(pool.getVersion('taskItem')).toBe(taskItemVersionBefore)
    })

    it('clears pending updates for removed objects', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent(), makeDatePoll()])
      pool.addPending('datePoll', 'poll-1', {
        deadline: '2099-01-01T00:00:00.000Z',
      })

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.hasPending('datePoll', 'poll-1')).toBe(false)
    })

    it('returns all removed objects for rollback', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent(), makeDatePoll(), makeDateRange()])

      const removed = pool.cascadeRemove('event', 'evt-1')

      expect(removed).toHaveLength(3)
      const ids = removed.map((entry) => entry.object.id)
      expect(ids).toContain('evt-1')
      expect(ids).toContain('poll-1')
      expect(ids).toContain('dr-1')
    })

    it('handles cascading a nonexistent object without throwing', () => {
      const pool = useObjectPoolStore()

      expect(() => pool.cascadeRemove('event', 'nonexistent')).not.toThrow()
    })

    it('removes event and its rsvps', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
        makeEvent(),
        makeRsvp({ id: 'r1', eventId: 'evt-1' }),
        makeRsvp({ id: 'r2', eventId: 'evt-1' }),
      ])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(pool.get('rsvp', 'r1')).toBeUndefined()
      expect(pool.get('rsvp', 'r2')).toBeUndefined()
    })

    it('removes event and its expenses with their participants', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
        makeEvent(),
        makeExpense({ id: 'exp-1', eventId: 'evt-1' }),
        makeExpenseParticipant({ id: 'ep-1', expenseId: 'exp-1' }),
        makeExpenseParticipant({ id: 'ep-2', expenseId: 'exp-1' }),
      ])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(pool.get('expense', 'exp-1')).toBeUndefined()
      expect(pool.get('expenseParticipant', 'ep-1')).toBeUndefined()
      expect(pool.get('expenseParticipant', 'ep-2')).toBeUndefined()
    })

    it('removes event and its settlements with their transfers', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
        makeEvent(),
        makeSettlement({ id: 'settlement-1', eventId: 'evt-1' }),
        makeSettlementTransfer({ id: 't1', settlementId: 'settlement-1' }),
        makeSettlementTransfer({ id: 't2', settlementId: 'settlement-1' }),
      ])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(pool.get('settlement', 'settlement-1')).toBeUndefined()
      expect(pool.get('settlementTransfer', 't1')).toBeUndefined()
      expect(pool.get('settlementTransfer', 't2')).toBeUndefined()
    })

    it('removes event and its choreRoster, chores, and assignments', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
        makeEvent(),
        makeChoreRoster({ id: 'roster-1', eventId: 'evt-1' }),
        makeChore({ id: 'chore-1', choreRosterId: 'roster-1' }),
        makeChoreAssignment({ id: 'assign-1', choreId: 'chore-1' }),
        makeChoreAssignment({ id: 'assign-2', choreId: 'chore-1' }),
      ])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(pool.get('choreRoster', 'roster-1')).toBeUndefined()
      expect(pool.get('chore', 'chore-1')).toBeUndefined()
      expect(pool.get('choreAssignment', 'assign-1')).toBeUndefined()
      expect(pool.get('choreAssignment', 'assign-2')).toBeUndefined()
    })

    it('removes settlement and its transfers when settlement is deleted directly', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
        makeSettlement(),
        makeSettlementTransfer({ id: 't1', settlementId: 'settlement-1' }),
      ])

      pool.cascadeRemove('settlement', 'settlement-1')

      expect(pool.get('settlement', 'settlement-1')).toBeUndefined()
      expect(pool.get('settlementTransfer', 't1')).toBeUndefined()
    })

    it('removes choreRoster, chores, and assignments when roster is deleted directly', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
        makeChoreRoster(),
        makeChore({ id: 'c1', choreRosterId: 'roster-1' }),
        makeChore({ id: 'c2', choreRosterId: 'roster-1' }),
        makeChoreAssignment({ id: 'a1', choreId: 'c1' }),
        makeChoreAssignment({ id: 'a2', choreId: 'c2' }),
      ])

      pool.cascadeRemove('choreRoster', 'roster-1')

      expect(pool.get('choreRoster', 'roster-1')).toBeUndefined()
      expect(pool.get('chore', 'c1')).toBeUndefined()
      expect(pool.get('chore', 'c2')).toBeUndefined()
      expect(pool.get('choreAssignment', 'a1')).toBeUndefined()
      expect(pool.get('choreAssignment', 'a2')).toBeUndefined()
    })

    it('removes expense and its participants when expense is deleted directly', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
        makeExpense(),
        makeExpenseParticipant({ id: 'ep-1', expenseId: 'exp-1' }),
        makeExpenseParticipant({ id: 'ep-2', expenseId: 'exp-1' }),
      ])

      pool.cascadeRemove('expense', 'exp-1')

      expect(pool.get('expense', 'exp-1')).toBeUndefined()
      expect(pool.get('expenseParticipant', 'ep-1')).toBeUndefined()
      expect(pool.get('expenseParticipant', 'ep-2')).toBeUndefined()
    })

    it('removes taskList and its items', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
        makeTaskList(),
        makeTaskItem({ id: 'i1', taskListId: 'list-1' }),
        makeTaskItem({ id: 'i2', taskListId: 'list-1' }),
      ])

      pool.cascadeRemove('taskList', 'list-1')

      expect(pool.get('taskList', 'list-1')).toBeUndefined()
      expect(pool.get('taskItem', 'i1')).toBeUndefined()
      expect(pool.get('taskItem', 'i2')).toBeUndefined()
    })

    it('does not remove sibling objects belonging to a different parent', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
        makeEvent({ id: 'evt-1' }),
        makeEvent({ id: 'evt-2' }),
        makeRsvp({ id: 'r1', eventId: 'evt-1' }),
        makeRsvp({ id: 'r2', eventId: 'evt-2' }),
        makeExpense({ id: 'e1', eventId: 'evt-1' }),
        makeExpense({ id: 'e2', eventId: 'evt-2' }),
      ])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('event', 'evt-2')).toBeDefined()
      expect(pool.get('rsvp', 'r2')).toBeDefined()
      expect(pool.get('expense', 'e2')).toBeDefined()
      expect(pool.get('rsvp', 'r1')).toBeUndefined()
      expect(pool.get('expense', 'e1')).toBeUndefined()
    })

    it('removes all children across every cascade chain in one event deletion', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
        makeEvent(),
        // Poll chain
        makeDatePoll(),
        makeDateRange(),
        makeVote(),
        // RSVP
        makeRsvp(),
        // Expense chain
        makeExpense(),
        makeExpenseParticipant(),
        // Settlement chain
        makeSettlement(),
        makeSettlementTransfer(),
        // Chore chain
        makeChoreRoster(),
        makeChore(),
        makeChoreAssignment(),
      ])

      pool.cascadeRemove('event', 'evt-1')

      const types = [
        'event',
        'datePoll',
        'dateRange',
        'vote',
        'rsvp',
        'expense',
        'expenseParticipant',
        'settlement',
        'settlementTransfer',
        'choreRoster',
        'chore',
        'choreAssignment',
      ] as const
      for (const type of types) {
        expect(pool.getAll(type)).toHaveLength(0)
      }
    })

    it('keeps reverse index consistent after remove so re-added children are found', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [
        makeEvent(),
        makeRsvp({ id: 'r1', eventId: 'evt-1' }),
        makeRsvp({ id: 'r2', eventId: 'evt-1' }),
      ])

      // Remove one child and re-add it
      pool.remove('rsvp', 'r1')
      pool.importObjects('workspace:test', [makeRsvp({ id: 'r1', eventId: 'evt-1' })])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('rsvp', 'r1')).toBeUndefined()
      expect(pool.get('rsvp', 'r2')).toBeUndefined()
    })

    it('keeps reverse index consistent after set so children added via set are cascaded', () => {
      const pool = useObjectPoolStore()
      pool.importObjects('workspace:test', [makeEvent()])
      pool.set('workspace:test', makeRsvp({ id: 'r1', eventId: 'evt-1' }))
      pool.set('workspace:test', makeRsvp({ id: 'r2', eventId: 'evt-1' }))

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('rsvp', 'r1')).toBeUndefined()
      expect(pool.get('rsvp', 'r2')).toBeUndefined()
    })

    it('rebuilds reverse index correctly after replaceObjects', async () => {
      const pool = useObjectPoolStore()
      // First populate with some objects
      pool.importObjects('workspace:test', [
        makeEvent({ id: 'evt-old' }),
        makeRsvp({ id: 'r-old', eventId: 'evt-old' }),
      ])

      // Replace with a different set
      await pool.replaceScope('workspace:test', [
        makeEvent({ id: 'evt-1' }),
        makeRsvp({ id: 'r1', eventId: 'evt-1' }),
        makeRsvp({ id: 'r2', eventId: 'evt-1' }),
      ])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.get('rsvp', 'r1')).toBeUndefined()
      expect(pool.get('rsvp', 'r2')).toBeUndefined()
      // Old objects should be gone from the replace
      expect(pool.get('rsvp', 'r-old')).toBeUndefined()
    })

    it('handles large numbers of children with O(1) index — all children removed', () => {
      const pool = useObjectPoolStore()
      const childCount = 200
      const children = Array.from({ length: childCount }, (_, i) =>
        makeRsvp({ id: `r${i}`, eventId: 'evt-1' })
      )
      pool.importObjects('workspace:test', [makeEvent(), ...children])

      pool.cascadeRemove('event', 'evt-1')

      expect(pool.getAll('rsvp')).toHaveLength(0)
    })
  })

  describe('importObjects reactivity debounce', () => {
    it('coalesces multiple importObjects calls within one tick into a single trigger', async () => {
      const pool = useObjectPoolStore()
      let triggerCount = 0

      // watchEffect runs once synchronously on setup, then re-runs whenever
      // a reactive dependency it read changes. getAll() reads typeVersions,
      // so it establishes a scoped reactivity dependency.
      const stop = watchEffect(() => {
        pool.getAll('event')
        triggerCount++
      })

      // Initial synchronous run
      expect(triggerCount).toBe(1)

      // Two separate importObjects calls — both in the same synchronous tick
      pool.importObjects('workspace:test', [makeEvent({ id: 'evt-1', name: 'A' })])
      pool.importObjects('workspace:test', [
        makeEvent({
          id: 'evt-2',
          name: 'B',
          updatedAt: '2026-06-01T00:00:00.000Z',
        }),
      ])

      // Triggers have NOT fired yet (microtask is still pending)
      expect(triggerCount).toBe(1)

      // Flush the microtask queue — exactly one trigger should fire for both imports
      await Promise.resolve()

      expect(triggerCount).toBe(2)

      stop()
    })

    it('fires separate triggers for imports in different event loop ticks', async () => {
      const pool = useObjectPoolStore()
      let triggerCount = 0

      const stop = watchEffect(() => {
        pool.getAll('event')
        triggerCount++
      })

      expect(triggerCount).toBe(1)

      // First tick
      pool.importObjects('workspace:test', [makeEvent({ id: 'evt-1' })])
      await Promise.resolve()
      expect(triggerCount).toBe(2)

      // Second tick (new event loop turn)
      pool.importObjects('workspace:test', [
        makeEvent({ id: 'evt-2', updatedAt: '2026-06-01T00:00:00.000Z' }),
      ])
      await Promise.resolve()
      expect(triggerCount).toBe(3)

      stop()
    })

    it('reflects all coalesced objects after the deferred trigger fires', async () => {
      const pool = useObjectPoolStore()

      pool.importObjects('workspace:test', [makeEvent({ id: 'evt-1', name: 'Alpha' })])
      pool.importObjects('workspace:test', [
        makeEvent({
          id: 'evt-2',
          name: 'Beta',
          updatedAt: '2026-06-01T00:00:00.000Z',
        }),
      ])

      await Promise.resolve()

      const all = pool.getAll('event')
      expect(all).toHaveLength(2)
      expect(all.map((e) => e.name).sort()).toEqual(['Alpha', 'Beta'])
    })
  })
})
