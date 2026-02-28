// Pool object types - matches backend pool serialization format
//
// TO ADD A NEW MODEL:
// 1. Add the type name to OBJECT_TYPES array
// 2. Add the interface to ObjectTypeMap
// That's it! PoolObject and ObjectType are derived automatically.

export type VoteResponse = 'yes' | 'no' | 'preferably_not'

// Base fields all pool objects must have
interface PoolObjectBase<T extends string> {
  id: string
  objectType: T
  updatedAt: string // ISO8601 with milliseconds
}

// ============================================================================
// OBJECT TYPE REGISTRY - Add new models here
// ============================================================================

export type DatePollStatus = 'open' | 'expired' | 'resolved'

export const OBJECT_TYPES = [
  'member',
  'event',
  'datePoll',
  'dateRange',
  'vote',
  'rsvp',
  'workspace',
  'taskList',
  'taskItem',
  'expense',
  'settlement',
  'settlementTransfer',
  'choreRoster',
  'chore',
  'choreAssignment',
] as const

export interface ObjectTypeMap {
  member: PoolObjectBase<'member'> & {
    workspaceId: string
    userId: string
    email: string
    name: string | null
    phoneNumber: string | null
    birthday: string | null
    locationName: string | null
    latitude: number | null
    longitude: number | null
    hasIban: boolean
    role: string
    createdAt: string
  }
  event: PoolObjectBase<'event'> & {
    name: string
    description: string | null
    startDate: string | null
    endDate: string | null
    locationName: string | null
    latitude: number | null
    longitude: number | null
    workspaceId: string
    userId: string
    datePollId: string | null
    rsvpIds: string[]
    createdAt: string
  }
  datePoll: PoolObjectBase<'datePoll'> & {
    eventId: string
    deadline: string
    selectedDateRangeId: string | null
    closedAt: string | null
    status: DatePollStatus
    dateRangeIds: string[]
    createdAt: string
  }
  dateRange: PoolObjectBase<'dateRange'> & {
    datePollId: string
    startDate: string
    endDate: string
    voteIds: string[]
  }
  vote: PoolObjectBase<'vote'> & {
    dateRangeId: string
    userId: string
    response: VoteResponse
    comment: string | null
    createdAt: string
  }
  rsvp: PoolObjectBase<'rsvp'> & {
    eventId: string
    userId: string
    attending: boolean
    startDate: string | null
    endDate: string | null
    createdAt: string
  }
  workspace: PoolObjectBase<'workspace'> & {
    name: string
    memberIds: string[]
    createdAt: string
  }
  taskList: PoolObjectBase<'taskList'> & {
    workspaceId: string
    userId: string | null
    name: string
    position: number
    createdAt: string
  }
  taskItem: PoolObjectBase<'taskItem'> & {
    taskListId: string
    userId: string | null
    content: string
    completedAt: string | null
    position: number
    createdAt: string
  }
  expense: PoolObjectBase<'expense'> & {
    eventId: string
    userId: string | null
    settlementId: string | null
    description: string
    amount: number
    startDate: string
    endDate: string
    createdAt: string
  }
  settlement: PoolObjectBase<'settlement'> & {
    eventId: string
    userId: string | null
    transferIds: string[]
    createdAt: string
  }
  settlementTransfer: PoolObjectBase<'settlementTransfer'> & {
    settlementId: string
    fromUserId: string | null
    toUserId: string | null
    amount: number
    paidAt: string | null
    createdAt: string
  }
  choreRoster: PoolObjectBase<'choreRoster'> & {
    eventId: string
    userId: string | null
    choreIds: string[]
    createdAt: string
  }
  chore: PoolObjectBase<'chore'> & {
    choreRosterId: string
    name: string
    peoplePerDay: number
    position: number
    assignmentIds: string[]
    createdAt: string
  }
  choreAssignment: PoolObjectBase<'choreAssignment'> & {
    choreId: string
    userId: string
    date: string
    pinned: boolean
    note: string | null
    createdAt: string
  }
}

// ============================================================================
// DERIVED TYPES - Don't modify these
// ============================================================================

export type ObjectType = (typeof OBJECT_TYPES)[number]
export type PoolObject = ObjectTypeMap[ObjectType]

// Convenience aliases for accessing specific pool types
export type PoolMember = ObjectTypeMap['member']
export type PoolEvent = ObjectTypeMap['event']
export type PoolDatePoll = ObjectTypeMap['datePoll']
export type PoolDateRange = ObjectTypeMap['dateRange']
export type PoolVote = ObjectTypeMap['vote']
export type PoolRsvp = ObjectTypeMap['rsvp']
export type PoolWorkspace = ObjectTypeMap['workspace']
export type PoolTaskList = ObjectTypeMap['taskList']
export type PoolTaskItem = ObjectTypeMap['taskItem']
export type PoolExpense = ObjectTypeMap['expense']
export type PoolSettlement = ObjectTypeMap['settlement']
export type PoolSettlementTransfer = ObjectTypeMap['settlementTransfer']
export type PoolChoreRoster = ObjectTypeMap['choreRoster']
export type PoolChore = ObjectTypeMap['chore']
export type PoolChoreAssignment = ObjectTypeMap['choreAssignment']

// API response wrapper - all endpoints include objects array
export interface PoolApiResponse {
  objects: PoolObject[]
}

// Pending update for optimistic updates
export interface PendingUpdate<T extends ObjectType = ObjectType> {
  id: string
  objectType: T
  objectId: string
  changes: Partial<ObjectTypeMap[T]>
  timestamp: number
}
