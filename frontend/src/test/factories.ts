import type { ObjectTypeMap } from '@/types/pool'
import type { useObjectPoolStore } from '@/stores/objectPool'
import { Scope } from '@/api/scope'

// ============================================================================
// Pool object factories
//
// Each factory returns a valid pool object with sensible defaults.
// Pass overrides to customise individual fields.
// ============================================================================

export function makeEvent(
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
    timezone: 'Europe/Amsterdam',
    workspaceId: 'ws-1',
    userId: 'user-1',
    datePollId: null,
    rsvpIds: [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeMember(
  overrides: Partial<ObjectTypeMap['member']> = {}
): ObjectTypeMap['member'] {
  return {
    id: 'mem-1',
    objectType: 'member',
    workspaceId: 'ws-1',
    userId: 'user-1',
    email: 'alice@example.com',
    name: 'Alice',
    phoneNumber: null,
    birthday: null,
    locationName: null,
    latitude: null,
    longitude: null,
    role: 'member',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeWorkspace(
  overrides: Partial<ObjectTypeMap['workspace']> = {}
): ObjectTypeMap['workspace'] {
  return {
    id: 'ws-1',
    objectType: 'workspace',
    name: 'Test Workspace',
    timezone: 'Europe/Amsterdam',
    memberIds: ['mem-1'],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeDatePoll(
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

export function makeDateRange(
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

export function makeVote(
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

// `createdByUserId` defaults to `null` (legacy / unknown actor) so tests
// don't accidentally render the "filed by X" badge. Tests that exercise
// on-behalf-of behaviour pass an explicit value via overrides.
export function makeRsvp(
  overrides: Partial<ObjectTypeMap['rsvp']> = {}
): ObjectTypeMap['rsvp'] {
  return {
    id: 'rsvp-1',
    objectType: 'rsvp',
    eventId: 'evt-1',
    userId: 'user-1',
    createdByUserId: null,
    attending: true,
    attendance: null,
    startDate: null,
    endDate: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeTaskList(
  overrides: Partial<ObjectTypeMap['taskList']> = {}
): ObjectTypeMap['taskList'] {
  return {
    id: 'list-1',
    objectType: 'taskList',
    workspaceId: 'ws-1',
    userId: null,
    name: 'Shopping',
    position: 1,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeTaskItem(
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

export function makeExpense(
  overrides: Partial<ObjectTypeMap['expense']> = {}
): ObjectTypeMap['expense'] {
  return {
    id: 'exp-1',
    objectType: 'expense',
    eventId: 'evt-1',
    userId: 'user-1',
    createdByUserId: null,
    settlementId: null,
    revertsExpenseId: null,
    description: 'Hotel',
    amount: 100,
    startDate: '2026-03-01',
    endDate: '2026-03-03',
    participantIds: [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeExpenseParticipant(
  overrides: Partial<ObjectTypeMap['expenseParticipant']> = {}
): ObjectTypeMap['expenseParticipant'] {
  return {
    id: 'ep-1',
    objectType: 'expenseParticipant',
    expenseId: 'exp-1',
    userId: 'user-1',
    factor: 1,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeSettlement(
  overrides: Partial<ObjectTypeMap['settlement']> = {}
): ObjectTypeMap['settlement'] {
  return {
    id: 'settle-1',
    objectType: 'settlement',
    eventId: 'evt-1',
    userId: 'user-1',
    previousSettlementId: null,
    transferIds: [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeSettlementTransfer(
  overrides: Partial<ObjectTypeMap['settlementTransfer']> = {}
): ObjectTypeMap['settlementTransfer'] {
  return {
    id: 'transfer-1',
    objectType: 'settlementTransfer',
    settlementId: 'settle-1',
    fromUserId: 'user-1',
    toUserId: 'user-2',
    amount: 50,
    paidAt: null,
    paidByUserId: null,
    supersededAt: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeChoreRoster(
  overrides: Partial<ObjectTypeMap['choreRoster']> = {}
): ObjectTypeMap['choreRoster'] {
  return {
    id: 'roster-1',
    objectType: 'choreRoster',
    eventId: 'evt-1',
    userId: 'user-1',
    choreIds: [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeChore(
  overrides: Partial<ObjectTypeMap['chore']> = {}
): ObjectTypeMap['chore'] {
  return {
    id: 'chore-1',
    objectType: 'chore',
    choreRosterId: 'roster-1',
    name: 'Dishes',
    peoplePerDay: 1,
    position: 1,
    time: null,
    assignmentIds: [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeChoreAssignment(
  overrides: Partial<ObjectTypeMap['choreAssignment']> = {}
): ObjectTypeMap['choreAssignment'] {
  return {
    id: 'assign-1',
    objectType: 'choreAssignment',
    choreId: 'chore-1',
    userId: 'user-1',
    date: '2026-03-10',
    pinned: false,
    note: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

export function makeWorkspaceInvite(
  overrides: Partial<ObjectTypeMap['workspaceInvite']> = {}
): ObjectTypeMap['workspaceInvite'] {
  return {
    id: 'invite-1',
    objectType: 'workspaceInvite',
    workspaceId: 'ws-1',
    invitedBy: 'user-1',
    email: 'bob@example.com',
    name: null,
    expiresAt: '2026-01-02T00:00:00.000Z',
    acceptedAt: null,
    lastRemindedAt: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

// ============================================================================
// seedPool helper
//
// Inserts one or more pool objects into an already-active objectPool store.
// Usage: seedPool(pool, makeEvent(), makeMember({ name: 'Bob' }))
// ============================================================================

type ObjectPoolStore = ReturnType<typeof useObjectPoolStore>

/**
 * Test-only scope used by seedPool. Pool reads are scope-agnostic, so it
 * doesn't matter what we tag fixtures with — but it does have to be *some*
 * scope, since every object in the pool now belongs to at least one.
 */
export const TEST_SCOPE = Scope.workspace('test')

export function seedPool(
  pool: ObjectPoolStore,
  ...objects: Parameters<ObjectPoolStore['importObjects']>[0]
): void {
  pool.importObjects(objects, { scope: TEST_SCOPE })
}
