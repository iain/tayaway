// Pool object types - matches backend pool serialization format

export type ObjectType = 'user' | 'event' | 'dateRange' | 'vote'

export type VoteResponse = 'yes' | 'no' | 'preferably_not'

// Base interface for all pool objects
export interface PoolObjectBase {
  id: string
  objectType: ObjectType
  updatedAt: string // ISO8601 with milliseconds
}

export interface PoolUser extends PoolObjectBase {
  objectType: 'user'
  email: string
  name: string | null
  createdAt: string
}

export interface PoolEvent extends PoolObjectBase {
  objectType: 'event'
  name: string
  description: string | null
  userId: string
  dateRangeIds: string[]
  createdAt: string
}

export interface PoolDateRange extends PoolObjectBase {
  objectType: 'dateRange'
  eventId: string
  startDate: string
  endDate: string
  voteIds: string[]
}

export interface PoolVote extends PoolObjectBase {
  objectType: 'vote'
  dateRangeId: string
  userId: string
  response: VoteResponse
  comment: string | null
  createdAt: string
}

// Union type of all pool objects
export type PoolObject = PoolUser | PoolEvent | PoolDateRange | PoolVote

// Type mapping for generic access
export interface ObjectTypeMap {
  user: PoolUser
  event: PoolEvent
  dateRange: PoolDateRange
  vote: PoolVote
}

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
