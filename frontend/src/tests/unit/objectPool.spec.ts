import { describe, it, expect, beforeEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import type { ObjectTypeMap } from '@/types/pool'

// ── Factories ──────────────────────────────────────────────────────────────

const T = '2026-01-01T00:00:00.000Z'

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
    createdAt: T,
    updatedAt: T,
    ...overrides,
  }
}

function makeDatePoll(
  overrides: Partial<ObjectTypeMap['datePoll']> = {}
): ObjectTypeMap['datePoll'] {
  return {
    id: 'poll-1',
    objectType: 'datePoll',
    eventId: 'evt-1',
    deadline: T,
    selectedDateRangeId: null,
    closedAt: null,
    status: 'open',
    dateRangeIds: [],
    createdAt: T,
    updatedAt: T,
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
    startDate: '2026-02-01',
    endDate: '2026-02-05',
    voteIds: [],
    updatedAt: T,
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
    createdAt: T,
    updatedAt: T,
    ...overrides,
  }
}

function makeRsvp(
  overrides: Partial<ObjectTypeMap['rsvp']> = {}
): ObjectTypeMap['rsvp'] {
  return {
    id: 'rsvp-1',
    objectType: 'rsvp',
    eventId: 'evt-1',
    userId: 'user-1',
    attending: true,
    startDate: null,
    endDate: null,
    createdAt: T,
    updatedAt: T,
    ...overrides,
  }
}

function makeExpense(
  overrides: Partial<ObjectTypeMap['expense']> = {}
): ObjectTypeMap['expense'] {
  return {
    id: 'exp-1',
    objectType: 'expense',
    eventId: 'evt-1',
    userId: 'user-1',
    settlementId: null,
    description: 'Dinner',
    amount: 50,
    startDate: '2026-01-01',
    endDate: '2026-01-01',
    participantIds: [],
    createdAt: T,
    updatedAt: T,
    ...overrides,
  }
}

function makeExpenseParticipant(
  overrides: Partial<ObjectTypeMap['expenseParticipant']> = {}
): ObjectTypeMap['expenseParticipant'] {
  return {
    id: 'ep-1',
    objectType: 'expenseParticipant',
    expenseId: 'exp-1',
    userId: 'user-2',
    createdAt: T,
    updatedAt: T,
    ...overrides,
  }
}

function makeSettlement(
  overrides: Partial<ObjectTypeMap['settlement']> = {}
): ObjectTypeMap['settlement'] {
  return {
    id: 'settlement-1',
    objectType: 'settlement',
    eventId: 'evt-1',
    userId: 'user-1',
    transferIds: [],
    createdAt: T,
    updatedAt: T,
    ...overrides,
  }
}

function makeSettlementTransfer(
  overrides: Partial<ObjectTypeMap['settlementTransfer']> = {}
): ObjectTypeMap['settlementTransfer'] {
  return {
    id: 'transfer-1',
    objectType: 'settlementTransfer',
    settlementId: 'settlement-1',
    fromUserId: 'user-2',
    toUserId: 'user-1',
    amount: 25,
    paidAt: null,
    createdAt: T,
    updatedAt: T,
    ...overrides,
  }
}

function makeChoreRoster(
  overrides: Partial<ObjectTypeMap['choreRoster']> = {}
): ObjectTypeMap['choreRoster'] {
  return {
    id: 'roster-1',
    objectType: 'choreRoster',
    eventId: 'evt-1',
    userId: 'user-1',
    choreIds: [],
    createdAt: T,
    updatedAt: T,
    ...overrides,
  }
}

function makeChore(
  overrides: Partial<ObjectTypeMap['chore']> = {}
): ObjectTypeMap['chore'] {
  return {
    id: 'chore-1',
    objectType: 'chore',
    choreRosterId: 'roster-1',
    name: 'Dishes',
    peoplePerDay: 1,
    position: 1,
    assignmentIds: [],
    createdAt: T,
    updatedAt: T,
    ...overrides,
  }
}

function makeChoreAssignment(
  overrides: Partial<ObjectTypeMap['choreAssignment']> = {}
): ObjectTypeMap['choreAssignment'] {
  return {
    id: 'assign-1',
    objectType: 'choreAssignment',
    choreId: 'chore-1',
    userId: 'user-1',
    date: '2026-02-01',
    pinned: false,
    note: null,
    createdAt: T,
    updatedAt: T,
    ...overrides,
  }
}

function makeTaskList(
  overrides: Partial<ObjectTypeMap['taskList']> = {}
): ObjectTypeMap['taskList'] {
  return {
    id: 'list-1',
    objectType: 'taskList',
    workspaceId: 'ws-1',
    userId: 'user-1',
    name: 'Shopping',
    position: 1,
    createdAt: T,
    updatedAt: T,
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
    userId: 'user-1',
    content: 'Milk',
    completedAt: null,
    position: 1,
    createdAt: T,
    updatedAt: T,
    ...overrides,
  }
}

// ── Tests ──────────────────────────────────────────────────────────────────

describe('objectPool cascadeRemove', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('removes event and its datePoll, dateRanges, and votes', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
      makeEvent(),
      makeDatePoll(),
      makeDateRange(),
      makeVote(),
    ])

    pool.cascadeRemove('event', 'evt-1')

    expect(pool.get('event', 'evt-1')).toBeUndefined()
    expect(pool.get('datePoll', 'poll-1')).toBeUndefined()
    expect(pool.get('dateRange', 'dr-1')).toBeUndefined()
    expect(pool.get('vote', 'vote-1')).toBeUndefined()
  })

  it('removes event and its rsvps', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
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
    pool.importObjects([
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
    pool.importObjects([
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
    pool.importObjects([
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
    pool.importObjects([
      makeSettlement(),
      makeSettlementTransfer({ id: 't1', settlementId: 'settlement-1' }),
    ])

    pool.cascadeRemove('settlement', 'settlement-1')

    expect(pool.get('settlement', 'settlement-1')).toBeUndefined()
    expect(pool.get('settlementTransfer', 't1')).toBeUndefined()
  })

  it('removes choreRoster, chores, and assignments when roster is deleted directly', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
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
    pool.importObjects([
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
    pool.importObjects([
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
    pool.importObjects([
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

  it('handles removing a non-existent object without error', () => {
    const pool = useObjectPoolStore()
    expect(() => pool.cascadeRemove('event', 'no-such-id')).not.toThrow()
  })

  it('removes all children across every cascade chain in one event deletion', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
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
})
