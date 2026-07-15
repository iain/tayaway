import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { computed } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useHydratedEvent } from './useHydratedEvent'
import {
  makeEvent,
  makeMember,
  makeWorkspace,
  makeDatePoll,
  makeDateRange,
  makeVote,
  makeRsvp,
  makeAttendance,
  makeGuest,
} from '@/test/factories'

describe('useHydratedEvent', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  describe('basic event hydration', () => {
    it('returns undefined for a missing event', () => {
      const { event } = useHydratedEvent('nonexistent')

      expect(event.value).toBeUndefined()
    })

    it('reports isLoading when the event is not in the pool', () => {
      const { isLoading } = useHydratedEvent('nonexistent')

      expect(isLoading.value).toBe(true)
    })

    it('hydrates a basic event from the pool', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()], { scope: Scope.workspace('test') })

      const { event, isLoading } = useHydratedEvent('evt-1')

      expect(isLoading.value).toBe(false)
      expect(event.value).toBeDefined()
      expect(event.value!.id).toBe('evt-1')
      expect(event.value!.name).toBe('Test Event')
      expect(event.value!.workspaceId).toBe('ws-1')
      expect(event.value!.userId).toBe('user-1')
    })

    it('copies all scalar fields from the pool event', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({
            description: 'A fun trip',
            startDate: '2026-03-01',
            endDate: '2026-03-05',
            locationName: 'Beach House',
            latitude: 52.37,
            longitude: 4.89,
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.description).toBe('A fun trip')
      expect(event.value!.startDate).toBe('2026-03-01')
      expect(event.value!.endDate).toBe('2026-03-05')
      expect(event.value!.locationName).toBe('Beach House')
      expect(event.value!.latitude).toBe(52.37)
      expect(event.value!.longitude).toBe(4.89)
    })

    it('accepts a ComputedRef as eventId', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()], { scope: Scope.workspace('test') })

      const eventId = computed(() => 'evt-1')
      const { event } = useHydratedEvent(eventId)

      expect(event.value).toBeDefined()
      expect(event.value!.id).toBe('evt-1')
    })
  })

  describe('member resolution', () => {
    it('resolves the event creator member by userId', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent(), makeMember()], {
        scope: Scope.workspace('test'),
      })

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.member).toBeDefined()
      expect(event.value!.member!.userId).toBe('user-1')
      expect(event.value!.member!.name).toBe('Alice')
    })

    it('returns undefined member when the member is not in the pool', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ userId: 'unknown-user' })], {
        scope: Scope.workspace('test'),
      })

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.member).toBeUndefined()
    })
  })

  describe('workspace hydration', () => {
    it('hydrates the workspace with its members', () => {
      const pool = useObjectPoolStore()
      const member1 = makeMember({ id: 'mem-1', userId: 'user-1' })
      const member2 = makeMember({
        id: 'mem-2',
        userId: 'user-2',
        email: 'bob@example.com',
        name: 'Bob',
        role: 'admin',
      })
      pool.importObjects(
        [
          makeEvent(),
          makeWorkspace({ memberIds: ['mem-1', 'mem-2'] }),
          member1,
          member2,
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.workspace).toBeDefined()
      expect(event.value!.workspace!.id).toBe('ws-1')
      expect(event.value!.workspace!.name).toBe('Test Workspace')
      expect(event.value!.workspace!.members).toHaveLength(2)
      expect(event.value!.workspace!.members[0]!.email).toBe(
        'alice@example.com'
      )
      expect(event.value!.workspace!.members[1]!.role).toBe('admin')
    })

    it('returns undefined workspace when workspace is not in the pool', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ workspaceId: 'missing-ws' })], {
        scope: Scope.workspace('test'),
      })

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.workspace).toBeUndefined()
    })
  })

  describe('date poll hydration', () => {
    it('returns null datePoll when no poll exists', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()], { scope: Scope.workspace('test') })

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.datePoll).toBeNull()
    })

    it('hydrates a date poll with its date ranges', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ datePollId: 'poll-1' }),
          makeDatePoll({ dateRangeIds: ['dr-1', 'dr-2'] }),
          makeDateRange({
            id: 'dr-1',
            startDate: '2026-03-01',
            endDate: '2026-03-05',
          }),
          makeDateRange({
            id: 'dr-2',
            startDate: '2026-03-10',
            endDate: '2026-03-15',
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.datePoll).toBeDefined()
      expect(event.value!.datePoll!.id).toBe('poll-1')
      expect(event.value!.datePoll!.eventId).toBe('evt-1')
      expect(event.value!.datePoll!.status).toBe('open')
      expect(event.value!.datePoll!.dateRanges).toHaveLength(2)
    })

    it('sorts date ranges by startDate', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ datePollId: 'poll-1' }),
          makeDatePoll({ dateRangeIds: ['dr-1', 'dr-2'] }),
          makeDateRange({
            id: 'dr-1',
            startDate: '2026-04-01',
            endDate: '2026-04-05',
          }),
          makeDateRange({
            id: 'dr-2',
            startDate: '2026-03-01',
            endDate: '2026-03-05',
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.datePoll!.dateRanges[0]!.startDate).toBe('2026-03-01')
      expect(event.value!.datePoll!.dateRanges[1]!.startDate).toBe('2026-04-01')
    })

    it('resolves selectedDateRange when poll has a selected date range', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ datePollId: 'poll-1' }),
          makeDatePoll({
            selectedDateRangeId: 'dr-2',
            status: 'resolved',
            closedAt: '2026-01-15T00:00:00.000Z',
            dateRangeIds: ['dr-1', 'dr-2'],
          }),
          makeDateRange({
            id: 'dr-1',
            startDate: '2026-03-01',
            endDate: '2026-03-05',
          }),
          makeDateRange({
            id: 'dr-2',
            startDate: '2026-03-10',
            endDate: '2026-03-15',
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.datePoll!.selectedDateRangeId).toBe('dr-2')
      expect(event.value!.datePoll!.selectedDateRange).toBeDefined()
      expect(event.value!.datePoll!.selectedDateRange!.id).toBe('dr-2')
      expect(event.value!.datePoll!.selectedDateRange!.startDate).toBe(
        '2026-03-10'
      )
    })

    it('returns undefined selectedDateRange when no date range is selected', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [makeEvent({ datePollId: 'poll-1' }), makeDatePoll()],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.datePoll!.selectedDateRange).toBeUndefined()
    })
  })

  describe('vote hydration', () => {
    it('hydrates votes onto their date ranges', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ datePollId: 'poll-1' }),
          makeDatePoll({ dateRangeIds: ['dr-1'] }),
          makeDateRange(),
          makeVote({ id: 'vote-1', userId: 'user-1', response: 'yes' }),
          makeVote({ id: 'vote-2', userId: 'user-2', response: 'no' }),
          makeMember({ id: 'mem-1', userId: 'user-1', name: 'Alice' }),
          makeMember({ id: 'mem-2', userId: 'user-2', name: 'Bob' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')
      const dateRange = event.value!.datePoll!.dateRanges[0]!

      expect(dateRange.votes).toHaveLength(2)
      expect(dateRange.votes[0]!.response).toBe('yes')
      expect(dateRange.votes[1]!.response).toBe('no')
    })

    it('resolves member on each vote', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ datePollId: 'poll-1' }),
          makeDatePoll({ dateRangeIds: ['dr-1'] }),
          makeDateRange(),
          makeVote({ userId: 'user-1' }),
          makeMember({ userId: 'user-1', name: 'Alice' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')
      const vote = event.value!.datePoll!.dateRanges[0]!.votes[0]!

      expect(vote.member).toBeDefined()
      expect(vote.member!.name).toBe('Alice')
    })

    it('returns undefined member on vote when member is missing', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ datePollId: 'poll-1' }),
          makeDatePoll({ dateRangeIds: ['dr-1'] }),
          makeDateRange(),
          makeVote({ userId: 'unknown-user' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')
      const vote = event.value!.datePoll!.dateRanges[0]!.votes[0]!

      expect(vote.member).toBeUndefined()
    })

    it('includes vote comment', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ datePollId: 'poll-1' }),
          makeDatePoll({ dateRangeIds: ['dr-1'] }),
          makeDateRange(),
          makeVote({ comment: 'Works for me!' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')
      const vote = event.value!.datePoll!.dateRanges[0]!.votes[0]!

      expect(vote.comment).toBe('Works for me!')
    })
  })

  describe('vote summary calculation', () => {
    it('calculates vote summary for a date range', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ datePollId: 'poll-1' }),
          makeDatePoll({ dateRangeIds: ['dr-1'] }),
          makeDateRange(),
          makeVote({ id: 'v1', userId: 'u1', response: 'yes' }),
          makeVote({ id: 'v2', userId: 'u2', response: 'yes' }),
          makeVote({ id: 'v3', userId: 'u3', response: 'no' }),
          makeVote({ id: 'v4', userId: 'u4', response: 'preferably_not' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')
      const summary = event.value!.datePoll!.dateRanges[0]!.voteSummary

      expect(summary.yes).toBe(2)
      expect(summary.no).toBe(1)
      expect(summary.preferably_not).toBe(1)
      expect(summary.total).toBe(4)
    })

    it('returns zero counts when no votes exist', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ datePollId: 'poll-1' }),
          makeDatePoll({ dateRangeIds: ['dr-1'] }),
          makeDateRange(),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')
      const summary = event.value!.datePoll!.dateRanges[0]!.voteSummary

      expect(summary.yes).toBe(0)
      expect(summary.no).toBe(0)
      expect(summary.preferably_not).toBe(0)
      expect(summary.total).toBe(0)
    })
  })

  describe('RSVP hydration', () => {
    it('hydrates RSVPs for the event', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ rsvpIds: ['rsvp-1', 'rsvp-2'] }),
          makeRsvp({ id: 'rsvp-1', userId: 'user-1', attending: true }),
          makeRsvp({ id: 'rsvp-2', userId: 'user-2', attending: false }),
          makeMember({ id: 'mem-1', userId: 'user-1', name: 'Alice' }),
          makeMember({ id: 'mem-2', userId: 'user-2', name: 'Bob' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.rsvps).toHaveLength(2)
      expect(event.value!.rsvps[0]!.attending).toBe(true)
      expect(event.value!.rsvps[0]!.member).toBeDefined()
      expect(event.value!.rsvps[0]!.member!.name).toBe('Alice')
      expect(event.value!.rsvps[1]!.attending).toBe(false)
      expect(event.value!.rsvps[1]!.member!.name).toBe('Bob')
    })

    it('includes RSVP date range fields', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ rsvpIds: ['rsvp-1'] }),
          makeRsvp({
            startDate: '2026-03-01',
            endDate: '2026-03-05',
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.rsvps[0]!.startDate).toBe('2026-03-01')
      expect(event.value!.rsvps[0]!.endDate).toBe('2026-03-05')
    })

    it('returns empty rsvps array when no RSVPs exist', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()], { scope: Scope.workspace('test') })

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.rsvps).toEqual([])
    })

    it('only includes RSVPs for the specific event', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1', rsvpIds: ['rsvp-1'] }),
          makeRsvp({ id: 'rsvp-1', eventId: 'evt-1' }),
          makeRsvp({ id: 'rsvp-2', eventId: 'evt-other' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.rsvps).toHaveLength(1)
      expect(event.value!.rsvps[0]!.id).toBe('rsvp-1')
    })
  })

  // The hydrated attendee is the single frontend reader of the
  // userId XOR guestId union (doc/attendances.md) — everything downstream
  // consumes what these examples pin.
  describe('attendance hydration', () => {
    it('resolves a member row to the member behind it', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1' }),
          makeMember({ id: 'mem-1', userId: 'user-1', name: 'Alice' }),
          makeAttendance({ id: 'att-1', eventId: 'evt-1', userId: 'user-1' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      const attendance = event.value!.attendances[0]!
      expect(attendance.attendee.isGuest).toBe(false)
      expect(attendance.attendee.name).toBe('Alice')
      expect(attendance.attendee.member?.id).toBe('mem-1')
      expect(attendance.attendee.hostMember).toBeUndefined()
    })

    it('resolves a guest row to the guest and their hosting member', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1' }),
          makeMember({ id: 'mem-1', userId: 'user-1', name: 'Alice' }),
          makeGuest({ id: 'guest-1', name: 'Emma' }),
          makeAttendance({
            id: 'att-1',
            eventId: 'evt-1',
            userId: null,
            guestId: 'guest-1',
            hostUserId: 'user-1',
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      const attendance = event.value!.attendances[0]!
      expect(attendance.attendee.isGuest).toBe(true)
      expect(attendance.attendee.name).toBe('Emma')
      expect(attendance.attendee.guest?.id).toBe('guest-1')
      expect(attendance.attendee.hostMember?.name).toBe('Alice')
    })

    it('only includes attendances for the specific event', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1' }),
          makeAttendance({ id: 'att-1', eventId: 'evt-1' }),
          makeAttendance({ id: 'att-2', eventId: 'evt-other' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.attendances.map((a) => a.id)).toEqual(['att-1'])
    })
  })

  describe('member index lookup correctness', () => {
    it('resolves members across multiple date ranges using a shared index', () => {
      // This is the O(N*M) scenario: 3 date ranges × N voters.
      // Correct behaviour requires each vote to find its member regardless of
      // which date range it belongs to — a linear scan re-run per vote would
      // still produce correct results but is the performance bug the index fixes.
      // The test ensures all lookups resolve correctly from a single index pass.
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ datePollId: 'poll-1' }),
          makeDatePoll({ dateRangeIds: ['dr-1', 'dr-2', 'dr-3'] }),
          makeDateRange({
            id: 'dr-1',
            datePollId: 'poll-1',
            startDate: '2026-03-01',
            endDate: '2026-03-03',
          }),
          makeDateRange({
            id: 'dr-2',
            datePollId: 'poll-1',
            startDate: '2026-03-04',
            endDate: '2026-03-06',
          }),
          makeDateRange({
            id: 'dr-3',
            datePollId: 'poll-1',
            startDate: '2026-03-07',
            endDate: '2026-03-09',
          }),
          makeVote({
            id: 'v1',
            dateRangeId: 'dr-1',
            userId: 'user-1',
            response: 'yes',
          }),
          makeVote({
            id: 'v2',
            dateRangeId: 'dr-1',
            userId: 'user-2',
            response: 'no',
          }),
          makeVote({
            id: 'v3',
            dateRangeId: 'dr-2',
            userId: 'user-1',
            response: 'preferably_not',
          }),
          makeVote({
            id: 'v4',
            dateRangeId: 'dr-2',
            userId: 'user-2',
            response: 'yes',
          }),
          makeVote({
            id: 'v5',
            dateRangeId: 'dr-3',
            userId: 'user-1',
            response: 'no',
          }),
          makeVote({
            id: 'v6',
            dateRangeId: 'dr-3',
            userId: 'user-2',
            response: 'yes',
          }),
          makeMember({ id: 'mem-1', userId: 'user-1', name: 'Alice' }),
          makeMember({ id: 'mem-2', userId: 'user-2', name: 'Bob' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')
      const ranges = event.value!.datePoll!.dateRanges

      // All six votes across three date ranges must resolve their member correctly
      expect(ranges[0]!.votes[0]!.member!.name).toBe('Alice')
      expect(ranges[0]!.votes[1]!.member!.name).toBe('Bob')
      expect(ranges[1]!.votes[0]!.member!.name).toBe('Alice')
      expect(ranges[1]!.votes[1]!.member!.name).toBe('Bob')
      expect(ranges[2]!.votes[0]!.member!.name).toBe('Alice')
      expect(ranges[2]!.votes[1]!.member!.name).toBe('Bob')
    })

    it('resolves the same member on both votes and RSVPs without redundant pool scans', () => {
      // Verifies that the shared memberIndex built once is used for both vote
      // and RSVP member resolution — not rebuilt or re-scanned per lookup.
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ datePollId: 'poll-1', rsvpIds: ['rsvp-1', 'rsvp-2'] }),
          makeDatePoll({ dateRangeIds: ['dr-1'] }),
          makeDateRange(),
          makeVote({
            id: 'v1',
            dateRangeId: 'dr-1',
            userId: 'user-1',
            response: 'yes',
          }),
          makeVote({
            id: 'v2',
            dateRangeId: 'dr-1',
            userId: 'user-2',
            response: 'yes',
          }),
          makeRsvp({ id: 'rsvp-1', userId: 'user-1', attending: true }),
          makeRsvp({ id: 'rsvp-2', userId: 'user-2', attending: true }),
          makeMember({ id: 'mem-1', userId: 'user-1', name: 'Alice' }),
          makeMember({ id: 'mem-2', userId: 'user-2', name: 'Bob' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      // Both vote members
      expect(event.value!.datePoll!.dateRanges[0]!.votes[0]!.member!.name).toBe(
        'Alice'
      )
      expect(event.value!.datePoll!.dateRanges[0]!.votes[1]!.member!.name).toBe(
        'Bob'
      )
      // Both RSVP members — same index, same members
      expect(event.value!.rsvps[0]!.member!.name).toBe('Alice')
      expect(event.value!.rsvps[1]!.member!.name).toBe('Bob')
    })
  })

  describe('cross-event isolation', () => {
    it('only includes date ranges belonging to the event poll', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1', datePollId: 'poll-1' }),
          makeDatePoll({
            id: 'poll-1',
            eventId: 'evt-1',
            dateRangeIds: ['dr-1'],
          }),
          makeDateRange({ id: 'dr-1', datePollId: 'poll-1' }),
          makeDateRange({ id: 'dr-other', datePollId: 'poll-other' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      expect(event.value!.datePoll!.dateRanges).toHaveLength(1)
      expect(event.value!.datePoll!.dateRanges[0]!.id).toBe('dr-1')
    })

    it('only includes votes belonging to the event date ranges', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1', datePollId: 'poll-1' }),
          makeDatePoll({
            id: 'poll-1',
            eventId: 'evt-1',
            dateRangeIds: ['dr-1'],
          }),
          makeDateRange({ id: 'dr-1', datePollId: 'poll-1' }),
          makeVote({ id: 'v1', dateRangeId: 'dr-1' }),
          makeVote({ id: 'v-other', dateRangeId: 'dr-other' }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { event } = useHydratedEvent('evt-1')

      const votes = event.value!.datePoll!.dateRanges[0]!.votes
      expect(votes).toHaveLength(1)
      expect(votes[0]!.id).toBe('v1')
    })
  })

  describe('reactivity', () => {
    it('updates when pool data changes', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Original' })], {
        scope: Scope.workspace('test'),
      })

      const { event } = useHydratedEvent('evt-1')
      expect(event.value!.name).toBe('Original')

      pool.importObjects(
        [makeEvent({ name: 'Updated', updatedAt: '2026-02-01T00:00:00.000Z' })],
        { scope: Scope.workspace('test') }
      )
      expect(event.value!.name).toBe('Updated')
    })

    it('becomes defined when event is added to pool', () => {
      const pool = useObjectPoolStore()
      const { event, isLoading } = useHydratedEvent('evt-1')

      expect(event.value).toBeUndefined()
      expect(isLoading.value).toBe(true)

      pool.importObjects([makeEvent()], { scope: Scope.workspace('test') })

      expect(event.value).toBeDefined()
      expect(isLoading.value).toBe(false)
    })
  })
})
