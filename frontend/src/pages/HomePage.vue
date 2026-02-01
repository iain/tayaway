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
  } catch (e) {
    error.value = 'Failed to connect to API'
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <main class="min-h-screen bg-gray-100 flex items-center justify-center">
    <div class="bg-white p-8 rounded-lg shadow-md text-center">
      <h1 class="text-3xl font-bold text-gray-900 mb-4">Tayaway</h1>
      <div v-if="loading" class="text-gray-500">Checking API status...</div>
      <div v-else-if="error" class="text-red-500">{{ error }}</div>
      <div v-else class="text-green-600">
        API Status: {{ healthStatus }}
      </div>
    </div>
  </main>
</template>
