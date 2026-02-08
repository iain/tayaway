import { useNotificationsStore, useObjectPoolStore } from '@/stores'
import type { PoolObject, ObjectType } from '@/types/pool'

export interface ApiResponse<T> {
  data: T
  status: number
}

interface DeletedObject {
  objectType: ObjectType
  id: string
}

// Process API response: import objects and remove deletions
function processPoolResponse(data: unknown): void {
  if (!data || typeof data !== 'object') return

  const pool = useObjectPoolStore()

  // Import new/updated objects
  if ('objects' in data && Array.isArray((data as { objects: unknown }).objects)) {
    pool.importObjects((data as { objects: PoolObject[] }).objects)
  }

  // Remove deleted objects
  if ('deleted' in data && Array.isArray((data as { deleted: unknown }).deleted)) {
    for (const item of (data as { deleted: DeletedObject[] }).deleted) {
      pool.remove(item.objectType, item.id)
    }
  }
}

export interface ApiError {
  message: string
  status: number
}

const SESSION_TOKEN_KEY = 'session_token'

export function getSessionToken(): string | null {
  return localStorage.getItem(SESSION_TOKEN_KEY)
}

export function setSessionToken(token: string): void {
  localStorage.setItem(SESSION_TOKEN_KEY, token)
}

export function clearSessionToken(): void {
  localStorage.removeItem(SESSION_TOKEN_KEY)
}

function getErrorMessage(status: number): string {
  switch (status) {
    case 400:
      return 'Invalid request. Please check your input and try again.'
    case 401:
      return 'You need to sign in to continue.'
    case 403:
      return 'You don\'t have permission to perform this action.'
    case 404:
      return 'The requested resource was not found.'
    case 422:
      return 'The request could not be processed. Please check your input.'
    case 500:
      return 'Something went wrong on our end. Please try again later.'
    case 502:
    case 503:
    case 504:
      return 'The server is temporarily unavailable. Please try again later.'
    default:
      return 'An unexpected error occurred. Please try again.'
  }
}

class ApiClient {
  private baseUrl: string

  constructor(baseUrl = '/api') {
    this.baseUrl = baseUrl
  }

  async get<T>(path: string): Promise<ApiResponse<T>> {
    return this.request<T>('GET', path)
  }

  async post<T>(path: string, body?: unknown): Promise<ApiResponse<T>> {
    return this.request<T>('POST', path, body)
  }

  async put<T>(path: string, body?: unknown): Promise<ApiResponse<T>> {
    return this.request<T>('PUT', path, body)
  }

  async patch<T>(path: string, body?: unknown): Promise<ApiResponse<T>> {
    return this.request<T>('PATCH', path, body)
  }

  async delete<T>(path: string): Promise<ApiResponse<T>> {
    return this.request<T>('DELETE', path)
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown
  ): Promise<ApiResponse<T>> {
    const url = `${this.baseUrl}${path}`
    const headers: HeadersInit = {
      'Content-Type': 'application/json',
    }

    const sessionToken = getSessionToken()
    if (sessionToken) {
      headers['Authorization'] = `Bearer ${sessionToken}`
    }

    const response = await fetch(url, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    })

    if (!response.ok) {
      const error: ApiError = {
        message: response.statusText,
        status: response.status,
      }

      // On 401 Unauthorized, clear the session token
      // The router guard will redirect to login on next navigation
      if (response.status === 401) {
        clearSessionToken()
      }

      const notificationsStore = useNotificationsStore()
      notificationsStore.showError(getErrorMessage(response.status))
      throw error
    }

    const data = await response.json() as T
    processPoolResponse(data)
    return { data, status: response.status }
  }
}

export const api = new ApiClient()
