import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { api, setSessionToken, clearSessionToken, getSessionToken } from '@/api/client'
import { useObjectPoolStore } from './objectPool'
import type { User, MagicLinkResponse, VerifyResponse, MeResponse, LogoutResponse } from '@/types'
import type { PoolObject } from '@/types/pool'

// Extended response types that include pool objects
interface MeResponseWithPool extends MeResponse {
  objects?: PoolObject[]
}

interface VerifyResponseWithPool extends VerifyResponse {
  objects?: PoolObject[]
}

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const loading = ref(false)
  const initialized = ref(false)

  const isAuthenticated = computed(() => user.value !== null)

  async function initialize(): Promise<void> {
    if (initialized.value) return

    const token = getSessionToken()
    if (!token) {
      initialized.value = true
      return
    }

    try {
      loading.value = true
      const response = await api.get<MeResponseWithPool>('/auth/me')

      // Import objects to pool if present
      if (response.data.objects) {
        const pool = useObjectPoolStore()
        pool.importObjects(response.data.objects)
      }

      user.value = response.data.user
    } catch {
      clearSessionToken()
      user.value = null
    } finally {
      loading.value = false
      initialized.value = true
    }
  }

  async function requestMagicLink(email: string): Promise<string> {
    const response = await api.post<MagicLinkResponse>('/auth/magic-link', { email })
    return response.data.message
  }

  async function verifyToken(token: string, email: string): Promise<User> {
    const response = await api.post<VerifyResponseWithPool>('/auth/verify', { token, email })

    // Import objects to pool if present
    if (response.data.objects) {
      const pool = useObjectPoolStore()
      pool.importObjects(response.data.objects)
    }

    setSessionToken(response.data.session_token)
    user.value = response.data.user
    return response.data.user
  }

  async function logout(): Promise<void> {
    try {
      await api.post<LogoutResponse>('/auth/logout')
    } finally {
      clearSessionToken()
      user.value = null
      // Reset pool on logout
      const pool = useObjectPoolStore()
      pool.$reset()
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
    $reset,
  }
})
