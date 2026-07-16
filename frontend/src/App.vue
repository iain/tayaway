<script setup lang="ts">
import { onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { RouterView } from 'vue-router'
import { useAuthStore, useCommandQueueStore } from '@/stores'
import { useWebSocketStore } from '@/stores/websocket'
import { poolPersistence } from '@/api/poolPersistence'
import { updateRequired } from '@/api/updateRequired'
import ToastContainer from '@/components/common/ToastContainer.vue'
import UpdateRequiredOverlay from '@/components/common/UpdateRequiredOverlay.vue'

const authStore = useAuthStore()
const commandQueueStore = useCommandQueueStore()
const { initialized } = storeToRefs(authStore)

// A wedged IndexedDB (e.g. a version-change open blocked forever by an old
// tab) must not keep the app from ever connecting — proceed without the
// cache after this long. Cursors won't be restored then, so the connect
// falls back to a full sync: slower, but correct.
const CACHE_HYDRATION_TIMEOUT_MS = 5_000

onMounted(async () => {
  await authStore.initialize()
  if (authStore.isAuthenticated) {
    // Cache hydration must complete before the command queue replays: a
    // replay rejection rolls back pending overlays by id, which only works
    // once loadFromCache has restored them, and the rollback only reaches
    // the IDB cache once startPersisting is registered.
    await Promise.race([
      poolPersistence.loadFromCache(),
      new Promise<void>((resolve) =>
        setTimeout(resolve, CACHE_HYDRATION_TIMEOUT_MS)
      ),
    ])
    poolPersistence.startPersisting()
    // The queue re-marks still-queued creates as temp before the socket
    // connects — a reconciliation full sync arriving first would otherwise
    // drop those optimistic objects.
    await commandQueueStore.initialize()
    // Connect last: loadFromCache restored the sync cursors, so the
    // partial-vs-full decision on the connect URL describes a cached
    // baseline that is actually in the pool.
    useWebSocketStore().connect()
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
  <UpdateRequiredOverlay v-if="updateRequired" />
</template>
