// Shared types for the frontend application

export interface User {
  id: string
  email: string
  name: string | null
  created_at: string
  updated_at: string
}

export interface MagicLinkResponse {
  message: string
}

export interface VerifyResponse {
  session_token: string
  user_id: string
}

export interface MeResponse {
  user_id: string
  email: string
  name: string | null
}

// Simple user type for auth responses (outside the object pool)
export interface AuthUser {
  id: string
  email: string
  name: string | null
}

export interface LogoutResponse {
  message: string
}

export interface Session {
  id: string
  created_at: string
  expires_at: string
  current: boolean
}

export interface SessionsResponse {
  sessions: Session[]
}

export interface AuthError {
  error: string
}

// Vote types
export type VoteResponse = 'yes' | 'no' | 'preferably_not'

export interface Vote {
  id: string
  date_range_id: string
  user_id: string
  user: User
  response: VoteResponse
  comment: string | null
  created_at: string
  updated_at: string
}

export interface VoteSummary {
  yes: number
  no: number
  preferably_not: number
  total: number
}

export interface VotesResponse {
  votes: Vote[]
}

export interface VoteRequestBody {
  date_range_id: string
  response: VoteResponse
  comment?: string
}

export interface VoteApiResponse {
  vote: Vote
}

// Event types
export interface DateRange {
  id: string
  start_date: string
  end_date: string
  votes: Vote[]
  vote_summary: VoteSummary
}

export interface Event {
  id: string
  name: string
  description: string | null
  user_id: string
  user: User
  date_ranges: DateRange[]
  created_at: string
  updated_at: string
}

export interface EventsResponse {
  events: Event[]
}

export interface EventResponse {
  event: Event
}

export interface CreateEventRequest {
  name: string
  description?: string
}

export interface UpdateEventRequest {
  name: string
  description?: string
}

// Member management types
export interface CreateMemberResponse {
  member_id: string
}

export interface CreateMemberRequest {
  name?: string
  email: string
}
