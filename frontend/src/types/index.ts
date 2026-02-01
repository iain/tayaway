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
  user: User
}

export interface MeResponse {
  user: User
}

export interface LogoutResponse {
  message: string
}

export interface AuthError {
  error: string
}

// Event types
export interface DateRange {
  id: string
  start_date: string
  end_date: string
}

export interface Event {
  id: string
  name: string
  description: string | null
  user_id: string
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
  date_ranges: { start_date: string; end_date: string }[]
}

export interface UpdateEventRequest {
  name: string
  description?: string
  date_ranges: { start_date: string; end_date: string }[]
}
