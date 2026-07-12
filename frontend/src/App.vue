<script setup lang="ts">
import { onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { RouterView } from 'vue-router'
import { useAuthStore, useCommandQueueStore } from '@/stores'
import { useWebSocketStore } from '@/stores/websocket'
import { poolPersistence } from '@/api/poolPersistence'
import ToastContainer from '@/components/common/ToastContainer.vue'

const authStore = useAuthStore()
const commandQueueStore = useCommandQueueStore()
const { initialized } = storeToRefs(authStore)

onMounted(async () => {
  await authStore.initialize()
  if (authStore.isAuthenticated) {
    // Cache hydration must complete before the command queue replays: a
    // replay rejection rolls back pending overlays by id, which only works
    // once loadFromCache has restored them, and the rollback only reaches
    // the IDB cache once startPersisting is registered.
    await poolPersistence.loadFromCache()
    poolPersistence.startPersisting()
    // Connect only after hydration: loadFromCache restores the sync
    // cursors, and the partial-vs-full decision on the connect URL is only
    // sound once the cached baseline those cursors describe is in the pool.
    useWebSocketStore().connect()
    await commandQueueStore.initialize()
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
    <p class="text-ink-placeholder mt-3 text-sm">Loading...</p>
  </div>
  <ToastContainer />
</template>
