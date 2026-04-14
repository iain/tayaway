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

    const { teardownSession } = await import('@/api/teardownSession')
    await teardownSession()

    const { default: router } = await import('@/router')
    await router.push({ name: 'login', query: { reason: 'session_revoked' } })
  } finally {
    handling = false
  }
}
