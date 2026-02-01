<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '@/api/client'
import { useAuth } from '@/composables/useAuth'

interface HealthResponse {
  status: string
}

const router = useRouter()
const { user, isAuthenticated, logout } = useAuth()

const healthStatus = ref<string>('')
const loading = ref(true)
const error = ref<string | null>(null)

onMounted(async () => {
  try {
    const response = await api.get<HealthResponse>('/health')
    healthStatus.value = response.data.status
  } catch {
    error.value = 'Failed to connect to API'
  } finally {
    loading.value = false
  }
})

async function handleLogout() {
  await logout()
  router.push('/login')
}
</script>

<template>
  <main class="min-h-screen bg-gray-100 flex items-center justify-center">
    <div class="bg-white p-8 rounded-lg shadow-md text-center">
      <h1 class="text-3xl font-bold text-gray-900 mb-4">
        Tayaway
      </h1>

      <div
        v-if="isAuthenticated"
        class="mb-4 p-3 bg-blue-50 border border-blue-200 rounded-md"
      >
        <p class="text-blue-700">
          Signed in as <strong>{{ user?.email }}</strong>
        </p>
        <button
          class="mt-2 py-1 px-3 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
          @click="handleLogout"
        >
          Sign out
        </button>
      </div>

      <div
        v-else
        class="mb-4"
      >
        <router-link
          to="/login"
          class="inline-block py-2 px-4 bg-blue-600 text-white font-medium rounded-md hover:bg-blue-700"
        >
          Sign in
        </router-link>
      </div>

      <div
        v-if="loading"
        class="text-gray-500"
      >
        Checking API status...
      </div>
      <div
        v-else-if="error"
        class="text-red-500"
      >
        {{ error }}
      </div>
      <div
        v-else
        class="text-green-600"
      >
        API Status: {{ healthStatus }}
      </div>
    </div>
  </main>
</template>
