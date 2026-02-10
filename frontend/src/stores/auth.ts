import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import {
  api,
  setSessionToken,
  clearSessionToken,
  getSessionToken,
} from '@/api/client'
import { useObjectPoolStore } from './objectPool'
import { useWebSocketStore } from './websocket'
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
    const token = getSessionToken()

    // If already initialized with a valid user, skip unless token changed
    if (initialized.value && user.value) return

    // If no token, mark as initialized and done
    if (!token) {
      initialized.value = true
      return
    }

    // Token exists but no user - (re)initialize auth
    try {
      loading.value = true
      const response = await api.get<MeResponse>('/auth/me')

      // Auth endpoints return user info directly (not via pool)
      user.value = {
        id: response.data.user_id,
        email: response.data.email,
        name: response.data.name,
      }

      // Connect WebSocket after successful auth
      const ws = useWebSocketStore()
      ws.connect()
    } catch {
      clearSessionToken()
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

  async function verifyToken(token: string, email: string): Promise<AuthUser> {
    const response = await api.post<VerifyResponse>('/auth/verify', {
      token,
      email,
    })

    setSessionToken(response.data.session_token)

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

      clearSessionToken()
      user.value = null
      // Reset pool on logout
      const pool = useObjectPoolStore()
      pool.$reset()
    }
  }

  async function updateName(name: string): Promise<void> {
    if (!user.value) return
    const response = await api.put<PoolApiResponse>(`/users/${user.value.id}`, {
      name,
    })
    // Update the auth store's user ref (pool auto-imports via client interceptor)
    const updatedUser = response.data.objects.find(
      (o) => o.objectType === 'user'
    )
    if (updatedUser && 'name' in updatedUser) {
      user.value.name = updatedUser.name
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
