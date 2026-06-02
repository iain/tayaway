<script setup lang="ts">
import { onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { RouterView } from 'vue-router'
import { useAuthStore, useCommandQueueStore } from '@/stores'
import { poolPersistence } from '@/api/poolPersistence'
import ToastContainer from '@/components/common/ToastContainer.vue'

const authStore = useAuthStore()
const commandQueueStore = useCommandQueueStore()
const { initialized } = storeToRefs(authStore)

onMounted(async () => {
  await authStore.initialize()
  if (authStore.isAuthenticated) {
    await commandQueueStore.initialize()
    await poolPersistence.loadFromCache()
    poolPersistence.startPersisting()
  }
})
</script>

<template>
  <RouterView v-if="initialized" />
  <div
    v-else
    class="bg-surface-page flex min-h-screen flex-col items-center justify-center"
  >
    <div
      class="inline-block h-10 w-10 animate-spin rounded-full border-4 border-amber-600 border-t-transparent"
    />
    <p class="mt-3 text-sm text-gray-500 dark:text-stone-400">Loading...</p>
  </div>
  <ToastContainer />
</template>
