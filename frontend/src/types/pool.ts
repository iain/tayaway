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
  'workspace',
] as const

export interface ObjectTypeMap {
  member: PoolObjectBase<'member'> & {
    workspaceId: string
    email: string
    name: string | null
    role: string
    createdAt: string
  }
  event: PoolObjectBase<'event'> & {
    name: string
    description: string | null
    startDate: string | null
    endDate: string | null
    workspaceId: string
    memberId: string
    datePollId: string | null
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
    memberId: string
    response: VoteResponse
    comment: string | null
    createdAt: string
  }
  workspace: PoolObjectBase<'workspace'> & {
    name: string
    memberIds: string[]
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
export type PoolWorkspace = ObjectTypeMap['workspace']

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
