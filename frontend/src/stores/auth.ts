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
} from '@/types'
import type { PoolApiResponse } from '@/types/pool'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<AuthUser | null>(null)
  const loading = ref(false)
  const initialized = ref(false)

  const isAuthenticated = computed(() => user.value !== null)

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

        // Connect WebSocket after successful auth
        const ws = useWebSocketStore()
        ws.connect()
      } else {
        user.value = null
      }
    } catch {
      user.value = null
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

      // Cookie is cleared by the backend response — no localStorage needed
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
    const { update } = useMutation()

    // Optimistically update the auth ref
    user.value.name = name

    try {
      const result = await update(
        'Failed to update name',
        'user',
        userId,
        { name },
        (commandQueue) =>
          commandQueue.enqueue<PoolApiResponse>('PUT', `/users/${userId}`, {
            name,
          })
      )
      if (!result.queued && user.value) {
        // Sync auth ref from pool (server response already imported)
        const pool = useObjectPoolStore()
        const poolUser = pool.get('user', userId)
        if (poolUser) {
          user.value.name = poolUser.name
        }
      }
    } catch (e) {
      // Restore previous name on failure (pool pending already rolled back by update())
      if (user.value) user.value.name = previousName
      throw e
    }
  }

  function $reset() {
    user.value = null
    loading.value = false
    initialized.value = false
  }

  return {
    user,
    loading,
    initialized,
    isAuthenticated,
    initialize,
    requestMagicLink,
    verifyToken,
    logout,
    updateName,
    $reset,
  }
})
