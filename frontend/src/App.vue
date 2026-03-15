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
  <div
    v-else
    class="flex min-h-screen flex-col items-center justify-center bg-gray-50 dark:bg-stone-900"
  >
    <div
      class="inline-block h-10 w-10 animate-spin rounded-full border-4 border-amber-600 border-t-transparent"
    />
    <p class="mt-3 text-sm text-gray-500 dark:text-stone-400">Loading...</p>
  </div>
  <ToastContainer />
</template>
