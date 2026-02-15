<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { api } from '@/api/client'

interface HealthResponse {
  status: string
}

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
</script>

<template>
  <div>
    <header class="mb-6">
      <h1
        class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
      >
        Dashboard
      </h1>
    </header>

    <div class="overflow-hidden rounded-lg bg-white shadow dark:bg-stone-800">
      <div class="px-4 py-5 sm:p-6">
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          API Status
        </h2>

        <div v-if="loading" class="text-gray-500 dark:text-stone-400">
          Checking API status...
        </div>
        <div v-else-if="error" class="text-red-600 dark:text-red-400">
          {{ error }}
        </div>
        <div v-else class="text-green-600 dark:text-green-400">
          Status: {{ healthStatus }}
        </div>
      </div>
    </div>
  </div>
</template>
