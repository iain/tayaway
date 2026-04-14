let handling = false

export async function handleSessionExpired(): Promise<void> {
  // Prevent multiple concurrent redirects
  if (handling) return
  handling = true

  try {
    const { useAuthStore } = await import('@/stores/auth')
    const authStore = useAuthStore()

    // Already logged out — nothing to do
    if (!authStore.isAuthenticated) return

    authStore.$reset()

    const { usePoolPersistence } =
      await import('@/composables/usePoolPersistence')
    const { stopPersisting } = usePoolPersistence()
    stopPersisting()

    const { useWebSocketStore } = await import('@/stores/websocket')
    useWebSocketStore().disconnect()

    const { useCommandQueueStore } = await import('@/stores/commandQueue')
    const commandQueue = useCommandQueueStore()
    await commandQueue.reset()

    const poolDb = await import('@/api/poolDb')
    await poolDb.clearAll()

    const { useObjectPoolStore } = await import('@/stores/objectPool')
    useObjectPoolStore().$reset()
    const { useWorkspaceStore } = await import('@/stores/workspace')
    useWorkspaceStore().$reset()

    localStorage.clear()
    const { clearUserCaches } = await import('@/api/clearUserCaches')
    await clearUserCaches()

    const { default: router } = await import('@/router')
    await router.push({ name: 'login', query: { reason: 'session_revoked' } })
  } finally {
    handling = false
  }
}
