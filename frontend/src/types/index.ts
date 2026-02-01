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
