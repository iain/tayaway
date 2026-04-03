import { useNotificationsStore, useObjectPoolStore } from '@/stores'
import type { PoolObject, ObjectType } from '@/types/pool'
import { handleSessionExpired } from '@/api/sessionExpired'

export interface ApiResponse<T> {
  data: T
  status: number
}

const DEFAULT_TIMEOUT_MS = 15_000

interface DeletedObject {
  objectType: ObjectType
  id: string
}

// Process API response: import objects and remove deletions
function processPoolResponse(data: unknown): void {
  if (!data || typeof data !== 'object') return

  const pool = useObjectPoolStore()

  // Import new/updated objects
  if (
    'objects' in data &&
    Array.isArray((data as { objects: unknown }).objects)
  ) {
    pool.importObjects((data as { objects: PoolObject[] }).objects)
  }

  // Remove deleted objects
  if (
    'deleted' in data &&
    Array.isArray((data as { deleted: unknown }).deleted)
  ) {
    for (const item of (data as { deleted: DeletedObject[] }).deleted) {
      pool.remove(item.objectType, item.id)
    }
  }
}

export interface ApiError {
  message: string
  status: number
}

function getErrorMessage(status: number): string {
  switch (status) {
    case 400:
      return 'Something was wrong with that request. Check your input and try again.'
    case 401:
      return 'You need to log in to continue.'
    case 403:
      return "You don't have permission to do that."
    case 404:
      return "That couldn't be found. It may have been deleted."
    case 422:
      return 'Check your input and try again.'
    case 500:
      return 'Something went wrong on our end. Try again in a moment.'
    case 502:
    case 503:
    case 504:
      return 'The server is temporarily unavailable. Try again in a moment.'
    default:
      return 'Something went wrong. Please try again.'
  }
}

class ApiClient {
  private baseUrl: string

  constructor(baseUrl = '/api') {
    this.baseUrl = baseUrl
  }

  async get<T>(
    path: string,
    options?: { signal?: AbortSignal }
  ): Promise<ApiResponse<T>> {
    return this.request<T>('GET', path, undefined, options)
  }

  async post<T>(
    path: string,
    body?: unknown,
    options?: { silent?: boolean; signal?: AbortSignal }
  ): Promise<ApiResponse<T>> {
    return this.request<T>('POST', path, body, options)
  }

  async put<T>(
    path: string,
    body?: unknown,
    options?: { signal?: AbortSignal }
  ): Promise<ApiResponse<T>> {
    return this.request<T>('PUT', path, body, options)
  }

  async patch<T>(
    path: string,
    body?: unknown,
    options?: { signal?: AbortSignal }
  ): Promise<ApiResponse<T>> {
    return this.request<T>('PATCH', path, body, options)
  }

  async delete<T>(
    path: string,
    options?: { signal?: AbortSignal }
  ): Promise<ApiResponse<T>> {
    return this.request<T>('DELETE', path, undefined, options)
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown,
    options?: { silent?: boolean; signal?: AbortSignal }
  ): Promise<ApiResponse<T>> {
    const url = `${this.baseUrl}${path}`
    const headers: HeadersInit = {
      'Content-Type': 'application/json',
      'X-CSRF-Protection': '1',
    }

    const timeoutSignal = AbortSignal.timeout(DEFAULT_TIMEOUT_MS)
    const signal = options?.signal
      ? AbortSignal.any([timeoutSignal, options.signal])
      : timeoutSignal

    const response = await fetch(url, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
      signal,
    })

    if (!response.ok) {
      // Redirect to login on 401 for non-auth endpoints
      const AUTH_PATHS = ['/auth/login-link', '/auth/verify', '/auth/me']
      if (
        response.status === 401 &&
        !AUTH_PATHS.some((p) => path.startsWith(p))
      ) {
        handleSessionExpired()
      }

      let serverMessage: string | undefined
      try {
        const body = (await response.json()) as unknown
        if (
          body &&
          typeof body === 'object' &&
          'error' in body &&
          typeof (body as { error: unknown }).error === 'string'
        ) {
          serverMessage = (body as { error: string }).error
        }
      } catch {
        // ignore parse errors
      }

      const error: ApiError = {
        message: serverMessage ?? response.statusText,
        status: response.status,
      }

      console.error(
        `API ${method} ${url} failed: ${response.status} ${error.message}`
      )

      if (!options?.silent) {
        const notificationsStore = useNotificationsStore()
        notificationsStore.showError(
          serverMessage || getErrorMessage(response.status)
        )
      }
      throw error
    }

    let data: T
    try {
      data = (await response.json()) as T
    } catch (parseError) {
      console.error(`API ${method} ${url} response parse failed:`, parseError)
      throw parseError
    }
    processPoolResponse(data)
    return { data, status: response.status }
  }
}

export const api = new ApiClient()
