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
  MagicLinkResponse,
  VerifyResponse,
  MeResponse,
  LogoutResponse,
  EmailChangeRequestResponse,
  EmailChangeVerifyResponse,
} from '@/types'
import type { PoolApiResponse } from '@/types/pool'

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

  async function initialize(): Promise<void> {
    // If already initialized with a valid user, skip
    if (initialized.value && user.value) return

    try {
      loading.value = true
      // Use raw fetch to silently probe — avoids error notification on 401
      // Timeout after 5s so the app doesn't hang on bad connections (iOS PWA)
      const controller = new AbortController()
      const timeout = setTimeout(() => controller.abort(), 5000)
      const response = await fetch('/api/auth/me', {
        signal: controller.signal,
      })
      clearTimeout(timeout)

      if (response.ok) {
        const data = (await response.json()) as MeResponse
        user.value = mapMeResponseToAuthUser(data)
        cacheUser(user.value)

        // Connect WebSocket after successful auth
        const ws = useWebSocketStore()
        ws.connect()
      } else if (response.status === 401 || response.status === 403) {
        // Session truly invalid — clear cache and require re-login
        user.value = null
        clearCachedUser()
      } else {
        // Server unavailable (5xx) — treat like network error, keep cached user
        user.value = getCachedUser()
        if (user.value) {
          const ws = useWebSocketStore()
          ws.connect()
        }
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
      user.value = getCachedUser()
      if (user.value) {
        const ws = useWebSocketStore()
        ws.connect()
      }
    } finally {
      loading.value = false
      initialized.value = true
    }
  }

  async function requestMagicLink(email: string): Promise<string> {
    const response = await api.post<MagicLinkResponse>('/auth/magic-link', {
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

    return verifiedUser
  }

  async function logout(): Promise<void> {
    try {
      await api.post<LogoutResponse>('/auth/logout')
    } finally {
      // Stop persisting pool changes before clearing state
      const { stopPersisting } = usePoolPersistence()
      stopPersisting()

      // Disconnect WebSocket first
      const ws = useWebSocketStore()
      ws.disconnect()

      // Clear command queue and pool cache
      const commandQueue = useCommandQueueStore()
      await commandQueue.reset()
      await poolDb.clearAll()

      clearCachedUser()
      user.value = null
      // Reset stores on logout
      const pool = useObjectPoolStore()
      pool.$reset()
      const workspaceStore = useWorkspaceStore()
      workspaceStore.$reset()
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
    if (fields.iban !== undefined) user.value.iban = fields.iban || null

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
    requestMagicLink,
    verifyToken,
    logout,
    updateProfile,
    updateName,
    requestEmailChange,
    verifyEmailChange,
    $reset,
  }
})
