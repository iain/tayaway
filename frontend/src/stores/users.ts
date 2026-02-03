import { ref } from 'vue'
import { defineStore } from 'pinia'
import { api } from '@/api/client'
import type { User, UsersResponse, UserResponse, CreateUserRequest } from '@/types'

export const useUsersStore = defineStore('users', () => {
  const users = ref<User[]>([])
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function fetchUsers(): Promise<User[]> {
    loading.value = true
    error.value = null
    try {
      const response = await api.get<UsersResponse>('/users')
      users.value = response.data.users
      return users.value
    } catch (e) {
      error.value = 'Failed to fetch users'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function createUser(data: CreateUserRequest): Promise<User> {
    loading.value = true
    error.value = null
    try {
      const response = await api.post<UserResponse>('/users', data)
      const newUser = response.data.user
      users.value = [...users.value, newUser].sort((a, b) => {
        const nameA = a.name || a.email
        const nameB = b.name || b.email
        return nameA.localeCompare(nameB)
      })
      return newUser
    } catch (e) {
      error.value = 'Failed to create user'
      throw e
    } finally {
      loading.value = false
    }
  }

  function $reset() {
    users.value = []
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
