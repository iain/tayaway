<script setup lang="ts">
import { onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { RouterView } from 'vue-router'
import { useAuthStore, useCommandQueueStore } from '@/stores'
import { usePoolPersistence } from '@/composables/usePoolPersistence'
import ToastContainer from '@/components/common/ToastContainer.vue'

const authStore = useAuthStore()
const commandQueueStore = useCommandQueueStore()
const { initialized } = storeToRefs(authStore)
const { loadFromCache, startPersisting } = usePoolPersistence()

onMounted(async () => {
  await authStore.initialize()
  if (authStore.isAuthenticated) {
    await commandQueueStore.initialize()
    await loadFromCache()
    startPersisting()
  }
})
</script>

<template>
  <RouterView v-if="initialized" />
  <div v-else class="flex min-h-screen items-center justify-center bg-gray-100">
    <div class="text-gray-500">Loading...</div>
  </div>
  <ToastContainer />
</template>
