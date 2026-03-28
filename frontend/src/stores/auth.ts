import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { api } from '@/api/client'
import { useCommandQueueStore } from './commandQueue'
import { useObjectPoolStore } from './objectPool'
import { useWebSocketStore } from './websocket'
import { useWorkspaceStore } from './workspace'
import { useMutation } from '@/composables/useMutation'

import * as poolDb from '@/api/poolDb'
import { usePoolPersistence } from '@/composables/usePoolPersistence'
import type {
  AuthUser,
  LoginLinkResponse,
  VerifyResponse,
  MeResponse,
  LogoutResponse,
  EmailChangeRequestResponse,
  EmailChangeVerifyResponse,
} from '@/types'
import type { PoolApiResponse } from '@/types/pool'

/** Mask an IBAN for display: "NL02 •••• •••• 5678" */
function maskIban(iban: string): string {
  if (iban.length <= 8) return iban
  const middle = Math.floor((iban.length - 8) / 4)
  return `${iban.slice(0, 4)} ${'•••• '.repeat(middle)}${iban.slice(-4)}`
}

const AUTH_USER_KEY = 'tayaway_auth_user'
const AUTH_USER_TTL_MS = 24 * 60 * 60 * 1000 // 24 hours

function cacheUser(u: AuthUser): void {
  // Omit iban before caching — sensitive data should not persist in localStorage
  const entry = {
    user: {
      id: u.id,
      email: u.email,
      name: u.name,
      phoneNumber: u.phoneNumber,
      birthday: u.birthday,
      locationName: u.locationName,
      latitude: u.latitude,
      longitude: u.longitude,
    },
    cachedAt: Date.now(),
  }
  localStorage.setItem(AUTH_USER_KEY, JSON.stringify(entry))
}

function getCachedUser(): AuthUser | null {
  try {
    const raw = localStorage.getItem(AUTH_USER_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as Record<string, unknown>
    // Support legacy format (no cachedAt) — treat as expired so stale sessions
    // are cleared on the next online boot
    const cachedAt =
      typeof parsed.cachedAt === 'number' ? parsed.cachedAt : null
    if (cachedAt === null || Date.now() - cachedAt > AUTH_USER_TTL_MS) {
      localStorage.removeItem(AUTH_USER_KEY)
      return null
    }
    return parsed.user as AuthUser
  } catch {
    return null
  }
}

function clearCachedUser(): void {
  localStorage.removeItem(AUTH_USER_KEY)
}

function mapMeResponseToAuthUser(data: MeResponse): AuthUser {
  return {
    id: data.user_id,
    email: data.email,
    name: data.name,
    phoneNumber: data.phoneNumber ?? null,
    birthday: data.birthday ?? null,
    locationName: data.locationName ?? null,
    latitude: data.latitude ?? null,
    longitude: data.longitude ?? null,
    iban: data.iban ?? null,
  }
}

export const useAuthStore = defineStore('auth', () => {
  const user = ref<AuthUser | null>(null)
  const loading = ref(false)
  const initialized = ref(false)

  const isAuthenticated = computed(() => user.value !== null)

  const currentUserId = computed(() => user.value?.id ?? null)

  /**
   * Fetch /api/auth/me with a 5s timeout and process the result.
   * Returns true if the session is valid, false if it is definitively invalid
   * (401/403), and null if the server was unreachable (network/timeout/5xx).
   */
  async function fetchMe(): Promise<boolean | null> {
    try {
      const response = await fetch('/api/auth/me', {
        signal: AbortSignal.timeout(5000),
      })

      if (response.ok) {
        const data = (await response.json()) as MeResponse
        user.value = mapMeResponseToAuthUser(data)
        cacheUser(user.value)
        return true
      } else if (response.status === 401 || response.status === 403) {
        return false
      } else {
        // Server unavailable (5xx) — treat as unreachable
        return null
      }
    } catch (e) {
      // Genuine network/abort errors are expected when offline or on slow
      // connections — fall back to cached user silently.
      // Any other error (programming bug, unexpected exception) should be
      // logged so it doesn't disappear unnoticed.
      const isNetworkError =
        e instanceof DOMException && e.name === 'AbortError'
          ? true
          : e instanceof TypeError &&
            /fetch|network|failed to fetch/i.test(e.message)
      if (!isNetworkError) {
        console.error('[auth] initialize() caught unexpected error:', e)
      }
      return null
    }
  }

  async function initialize(): Promise<void> {
    // If already initialized with a valid user, skip
    if (initialized.value && user.value) return

    const cached = getCachedUser()

    if (cached) {
      // Render immediately from cache — don't block navigation on the network.
      user.value = cached
      initialized.value = true

      // Validate the session in the background. If 401/403, redirect to login.
      validateInBackground()
      return
    }

    // No cache — block until the network responds so we know whether to render
    // protected content or redirect to login.
    try {
      loading.value = true
      const valid = await fetchMe()

      if (valid === true) {
        // fetchMe() already set user.value and cached the user
        const ws = useWebSocketStore()
        ws.connect()
      } else if (valid === false) {
        // Session truly invalid — clear cache and require re-login
        user.value = null
        clearCachedUser()
      } else {
        // Server unreachable — no cached user, treat as logged out
        user.value = null
      }
    } finally {
      loading.value = false
      initialized.value = true
    }
  }

  /**
   * Re-validate the cached session against /api/auth/me in the background.
   * Called after a cache-hit in initialize() so the UI renders immediately
   * while we confirm the session is still live.
   *
   * - 200: refresh user data and connect WebSocket
   * - 401/403: clear state and redirect to /login
   * - Network error / 5xx: keep the cached state, connect WebSocket optimistically
   */
  function validateInBackground(): void {
    // Connect WebSocket optimistically — the server will reject the ticket
    // if the session is invalid, at which point we'll redirect.
    const ws = useWebSocketStore()
    ws.connect()

    fetchMe()
      .then(async (valid) => {
        if (valid === true) {
          // Session confirmed — WebSocket already connected, nothing else to do
        } else if (valid === false) {
          // Session expired — full cleanup and redirect to login
          const { handleSessionExpired } = await import('@/api/sessionExpired')
          await handleSessionExpired()
        }
        // null (network error / 5xx): keep cached state, stay connected
      })
      .catch((e: unknown) => {
        // Unexpected error in the background validator — log but don't crash
        console.error(
          '[auth] validateInBackground() caught unexpected error:',
          e
        )
      })
  }

  async function requestLoginLink(email: string): Promise<string> {
    const response = await api.post<LoginLinkResponse>('/auth/login-link', {
      email,
    })
    return response.data.message
  }

  async function verifyToken(token: string): Promise<AuthUser> {
    await api.post<VerifyResponse>('/auth/verify', { token })

    // Cookie is set by the backend response — no localStorage needed

    // After verify, we need to fetch user info
    const meResponse = await api.get<MeResponse>('/auth/me')
    const verifiedUser = mapMeResponseToAuthUser(meResponse.data)
    user.value = verifiedUser
    cacheUser(verifiedUser)

    // Connect WebSocket after successful verification
    const ws = useWebSocketStore()
    ws.connect()

    // Resume any commands that were preserved when the session expired
    const commandQueue = useCommandQueueStore()
    if (commandQueue.pendingCount > 0) {
      commandQueue.processQueue()
    }

    return verifiedUser
  }

  async function logout(): Promise<void> {
    try {
      await api.post<LogoutResponse>('/auth/logout')
    } finally {
      // Stop persisting pool changes before clearing state
      const { stopPersisting } = usePoolPersistence()
      stopPersisting()

      // Disconnect WebSocket to stop reconnect loops
      const ws = useWebSocketStore()
      ws.disconnect()

      // Clear queued commands and IndexedDB cache
      const commandQueue = useCommandQueueStore()
      await commandQueue.reset()
      await poolDb.clearAll()

      // Reset all Pinia stores
      clearCachedUser()
      user.value = null
      useObjectPoolStore().$reset()
      useWorkspaceStore().$reset()

      // Wipe all client-side storage
      localStorage.clear()
      try {
        const keys = await caches.keys()
        await Promise.all(keys.map((k) => caches.delete(k)))
      } catch {
        // Caches API may be unavailable
      }
    }
  }

  interface ProfileFields {
    name?: string
    phoneNumber?: string | null
    birthday?: string | null
    locationName?: string | null
    latitude?: number | null
    longitude?: number | null
    iban?: string | null
  }

  async function updateProfile(fields: ProfileFields): Promise<void> {
    if (!user.value) return
    const previousUser = { ...user.value }
    const userId = user.value.id
    const pool = useObjectPoolStore()
    const member = pool.findBy('member', 'userId', userId)
    const { mutate, update } = useMutation()

    // Optimistically update the auth ref
    if (fields.name !== undefined) user.value.name = fields.name
    if (fields.phoneNumber !== undefined)
      user.value.phoneNumber = fields.phoneNumber
    if (fields.birthday !== undefined) user.value.birthday = fields.birthday
    if (fields.locationName !== undefined)
      user.value.locationName = fields.locationName
    if (fields.latitude !== undefined) user.value.latitude = fields.latitude
    if (fields.longitude !== undefined) user.value.longitude = fields.longitude
    if (fields.iban !== undefined)
      user.value.iban = fields.iban ? maskIban(fields.iban) : null

    try {
      const apiCall = (commandQueue: ReturnType<typeof useCommandQueueStore>) =>
        commandQueue.enqueue<PoolApiResponse>('PUT', `/users/${userId}`, fields)

      // Build optimistic pool changes from provided fields
      const poolChanges: Record<string, unknown> = {}
      if (fields.name !== undefined) poolChanges.name = fields.name
      if (fields.phoneNumber !== undefined)
        poolChanges.phoneNumber = fields.phoneNumber
      if (fields.birthday !== undefined) poolChanges.birthday = fields.birthday
      if (fields.locationName !== undefined)
        poolChanges.locationName = fields.locationName
      if (fields.latitude !== undefined) poolChanges.latitude = fields.latitude
      if (fields.longitude !== undefined)
        poolChanges.longitude = fields.longitude
      if (fields.iban !== undefined) poolChanges.hasIban = !!fields.iban

      const result = member
        ? await update(
            'Failed to update profile',
            'member',
            member.id,
            poolChanges,
            apiCall
          )
        : await mutate('Failed to update profile', apiCall)

      if (!result.queued && user.value) {
        const poolMember = member ? pool.get('member', member.id) : null
        if (poolMember) {
          user.value.name = poolMember.name
          user.value.phoneNumber = poolMember.phoneNumber
          user.value.birthday = poolMember.birthday
          user.value.locationName = poolMember.locationName
          user.value.latitude = poolMember.latitude
          user.value.longitude = poolMember.longitude
          user.value.iban = poolMember.hasIban ? user.value.iban : null
        }
      }
      if (user.value) cacheUser(user.value)
    } catch (e) {
      // Restore previous state on failure
      if (user.value) Object.assign(user.value, previousUser)
      throw e
    }
  }

  async function updateName(name: string): Promise<void> {
    return updateProfile({ name })
  }

  async function requestEmailChange(email: string): Promise<string> {
    const response = await api.post<EmailChangeRequestResponse>(
      '/users/email-change/request',
      { email }
    )
    return response.data.message
  }

  async function verifyEmailChange(token: string): Promise<string> {
    const response = await api.post<EmailChangeVerifyResponse>(
      '/users/email-change/verify',
      { token }
    )

    // If authenticated, refresh user info
    if (user.value) {
      try {
        const meResponse = await api.get<MeResponse>('/auth/me')
        user.value = mapMeResponseToAuthUser(meResponse.data)
        cacheUser(user.value)
      } catch {
        // May not be authenticated (different browser) — that's fine
      }
    }

    return response.data.message
  }

  function $reset() {
    clearCachedUser()
    user.value = null
    loading.value = false
    initialized.value = false
  }

  return {
    user,
    loading,
    initialized,
    isAuthenticated,
    currentUserId,
    initialize,
    requestLoginLink,
    verifyToken,
    logout,
    updateProfile,
    updateName,
    requestEmailChange,
    verifyEmailChange,
    $reset,
  }
})
