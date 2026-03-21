// Shared types for the frontend application

import type { VoteResponse } from '@/types/pool'

export interface LoginLinkResponse {
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
  phoneNumber: string | null
  birthday: string | null
  locationName: string | null
  latitude: number | null
  longitude: number | null
  iban: string | null
}

// Simple user type for auth responses (outside the object pool)
export interface AuthUser {
  id: string
  email: string
  name: string | null
  phoneNumber: string | null
  birthday: string | null
  locationName: string | null
  latitude: number | null
  longitude: number | null
  iban: string | null
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

// Vote types
export type { VoteResponse }

export interface VoteRequestBody {
  date_range_id: string
  response: VoteResponse
  comment?: string
}

// Event types
export interface CreateEventRequest {
  name: string
  description?: string
  startDate?: string
  endDate?: string
  locationName?: string
  latitude?: number
  longitude?: number
}

export interface UpdateEventRequest {
  name: string
  description?: string
  startDate?: string | null
  endDate?: string | null
  locationName?: string
  latitude?: number
  longitude?: number
}

// Invite types
export interface CreateInviteRequest {
  email: string
  name?: string
  workspace_id: string
}

export interface InviteInfoResponse {
  workspaceName: string
  email: string
}

// Email change types
export interface EmailChangeRequestResponse {
  message: string
}

export interface EmailChangeVerifyResponse {
  message: string
}
