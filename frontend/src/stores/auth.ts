import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { api } from '@/api/client'
import { useCommandQueueStore } from './commandQueue'
import { useObjectPoolStore } from './objectPool'
import { useWebSocketStore } from './websocket'
import { useWorkspaceStore } from './workspace'
import { useMutation } from '@/composables/useMutation'

import * as poolDb from '@/api/poolDb'
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

function cacheUser(u: AuthUser): void {
  localStorage.setItem(AUTH_USER_KEY, JSON.stringify(u))
}

function getCachedUser(): AuthUser | null {
  try {
    const raw = localStorage.getItem(AUTH_USER_KEY)
    return raw ? (JSON.parse(raw) as AuthUser) : null
  } catch {
    return null
  }
}

function clearCachedUser(): void {
  localStorage.removeItem(AUTH_USER_KEY)
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
      const response = await fetch('/api/auth/me')

      if (response.ok) {
        const data = (await response.json()) as MeResponse
        user.value = {
          id: data.user_id,
          email: data.email,
          name: data.name,
        }
        cacheUser(user.value)

        // Connect WebSocket after successful auth
        const ws = useWebSocketStore()
        ws.connect()
      } else {
        // Session truly invalid (401/403) — clear cache
        user.value = null
        clearCachedUser()
      }
    } catch {
      // Network error — fall back to cached user
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
    const verifiedUser: AuthUser = {
      id: meResponse.data.user_id,
      email: meResponse.data.email,
      name: meResponse.data.name,
    }
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

  async function updateName(name: string): Promise<void> {
    if (!user.value) return
    const previousName = user.value.name
    const userId = user.value.id
    const pool = useObjectPoolStore()
    const member = pool.findBy('member', 'userId', userId)
    const { mutate, update } = useMutation()

    // Optimistically update the auth ref
    user.value.name = name

    try {
      const apiCall = (commandQueue: ReturnType<typeof useCommandQueueStore>) =>
        commandQueue.enqueue<PoolApiResponse>('PUT', `/users/${userId}`, {
          name,
        })

      // If the member is in the pool, use optimistic pool update; otherwise just mutate
      const result = member
        ? await update(
            'Failed to update name',
            'member',
            member.id,
            { name },
            apiCall
          )
        : await mutate('Failed to update name', apiCall)

      if (!result.queued && user.value) {
        // Sync auth ref from pool (server response already imported)
        const poolMember = member ? pool.get('member', member.id) : null
        if (poolMember) {
          user.value.name = poolMember.name
        }
      }
      if (user.value) cacheUser(user.value)
    } catch (e) {
      // Restore previous name on failure (pool pending already rolled back by update())
      if (user.value) user.value.name = previousName
      throw e
    }
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
        user.value = {
          id: meResponse.data.user_id,
          email: meResponse.data.email,
          name: meResponse.data.name,
        }
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
    updateName,
    requestEmailChange,
    verifyEmailChange,
    $reset,
  }
})
