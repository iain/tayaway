import { useNotificationsStore } from '@/stores'
import { processPoolResponse } from '@/api/processPoolResponse'
import { handleSessionExpired } from '@/api/sessionExpired'

export interface ApiResponse<T> {
  data: T
  status: number
}

const DEFAULT_TIMEOUT_MS = 15_000

export interface ApiError {
  message: string
  status: number
}

export interface MutationOptions {
  silent?: boolean
  signal?: AbortSignal
  // Sent as the `Idempotency-Key` header. Only the offline command queue
  // sets this today; the server uses it to dedupe retries of the same
  // logical mutation.
  idempotencyKey?: string
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

/**
 * Low-level HTTP client. Pure: no side effects on application state.
 *
 * Prefer the pool-aware `api` export below for reads that expect the
 * response to hydrate the object pool, and prefer `useMutation` (which
 * goes through the offline command queue) for writes that produce pool
 * changes. `rawApi` is for the handful of flows where neither applies:
 *  - auth (login, verify, logout, passkeys, email change)
 *  - session management
 *  - WebSocket ticket fetch
 *  - invite info/accept
 *  - internal use by the command queue itself when replaying mutations
 */
class RawApiClient {
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
    options?: MutationOptions
  ): Promise<ApiResponse<T>> {
    return this.request<T>('POST', path, body, options)
  }

  async put<T>(
    path: string,
    body?: unknown,
    options?: MutationOptions
  ): Promise<ApiResponse<T>> {
    return this.request<T>('PUT', path, body, options)
  }

  async patch<T>(
    path: string,
    body?: unknown,
    options?: MutationOptions
  ): Promise<ApiResponse<T>> {
    return this.request<T>('PATCH', path, body, options)
  }

  async delete<T>(
    path: string,
    options?: MutationOptions
  ): Promise<ApiResponse<T>> {
    return this.request<T>('DELETE', path, undefined, options)
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown,
    options?: MutationOptions
  ): Promise<ApiResponse<T>> {
    const url = `${this.baseUrl}${path}`
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'X-CSRF-Protection': '1',
    }
    if (options?.idempotencyKey) {
      headers['Idempotency-Key'] = options.idempotencyKey
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
    return { data, status: response.status }
  }
}

/**
 * Raw HTTP client. Use only for endpoints that don't return pool objects
 * or that need explicit control over pool hydration (see RawApiClient
 * docstring above for the list).
 */
export const rawApi = new RawApiClient()

/**
 * Pool-aware HTTP client for GET requests that return pool objects. The
 * response body is automatically passed through processPoolResponse so
 * entities land in the local object pool.
 *
 * Mutations are intentionally NOT exposed here — they must flow through
 * `useMutation` so they participate in the offline command queue and
 * optimistic-update lifecycle. If you need to call a mutation endpoint
 * without those guarantees (auth, session, invite, etc.), use `rawApi`.
 */
export const api = {
  async get<T>(
    path: string,
    options?: { signal?: AbortSignal }
  ): Promise<ApiResponse<T>> {
    const response = await rawApi.get<T>(path, options)
    processPoolResponse(response.data)
    return response
  },
}
