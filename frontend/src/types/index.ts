// Shared types for the frontend application

import type { VoteResponse } from '@/types/pool'
import type {
  PublicKeyCredentialCreationOptionsJSON,
  PublicKeyCredentialRequestOptionsJSON,
} from '@simplewebauthn/browser'

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
  ibanHolderName: string | null
  // The user's display-zone preference. null means "follow this device".
  timezone: string | null
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
  ibanHolderName: string | null
  // Display-zone preference; null means "follow this device".
  timezone: string | null
}

export interface LogoutResponse {
  message: string
}

export interface Session {
  id: string
  created_at: string
  expires_at: string
  last_active_at: string | null
  current: boolean
  city: string | null
  country: string | null
  browser_name: string | null
  os_name: string | null
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
  // IANA zone, derived from the location (blank => workspace default).
  timezone?: string
}

export interface UpdateEventRequest {
  name: string
  description?: string
  startDate?: string | null
  endDate?: string | null
  locationName?: string
  latitude?: number
  longitude?: number
  // IANA zone; omit/blank to leave unchanged.
  timezone?: string
}

// Invite types
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

// Passkey types
export interface Passkey {
  id: string
  name: string | null
  aaguid: string | null
  createdAt: string
}

export interface PasskeysListResponse {
  passkeys: Passkey[]
}

export interface PasskeyRegistrationBeginResponse {
  options: PublicKeyCredentialCreationOptionsJSON
  challengeToken: string
}

export interface PasskeyAuthenticationBeginResponse {
  options: PublicKeyCredentialRequestOptionsJSON
  challengeToken: string
}

export interface PasskeyRegistrationResponse {
  passkey: Passkey
}

export interface PasskeyDeleteResponse {
  message: string
}
