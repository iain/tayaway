import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { api } from '@/api/client'
import { useObjectPoolStore } from './objectPool'
import type { CreateUserRequest, CreateUserResponse } from '@/types'
import type { PoolApiResponse, PoolUser } from '@/types/pool'

interface CreateUserResponseWithPool extends CreateUserResponse {
  objects?: PoolApiResponse['objects']
}

export const useUsersStore = defineStore('users', () => {
  const loading = ref(false)
  const error = ref<string | null>(null)

  // Users are derived from the pool
  const users = computed((): PoolUser[] => {
    const pool = useObjectPoolStore()
    return pool.getAll('user').sort((a, b) => {
      const nameA = a.name || a.email
      const nameB = b.name || b.email
      return nameA.localeCompare(nameB)
    })
  })

  async function fetchUsers(): Promise<PoolUser[]> {
    loading.value = true
    error.value = null
    try {
      // Response objects are automatically imported by API client
      await api.get<PoolApiResponse>('/users')
      return users.value
    } catch (e) {
      error.value = 'Failed to fetch users'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function createUser(data: CreateUserRequest): Promise<PoolUser> {
    loading.value = true
    error.value = null
    try {
      const response = await api.post<CreateUserResponseWithPool>('/users', data)

      // Get created user from pool
      const pool = useObjectPoolStore()
      const newUser = pool.get('user', response.data.user_id)
      if (!newUser) {
        throw new Error('User not found in pool after creation')
      }
      return newUser
    } catch (e) {
      error.value = 'Failed to create user'
      throw e
    } finally {
      loading.value = false
    }
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return {
    users,
    loading,
    error,
    fetchUsers,
    createUser,
    $reset,
  }
})
