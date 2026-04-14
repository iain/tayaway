/**
 * Shared session teardown used by both the logout flow and the session-
 * expired flow. Stops pool persistence, disconnects the WebSocket, drains
 * and clears the command queue, wipes the IndexedDB pool cache, resets
 * Pinia stores that are safe to reset from outside, clears localStorage,
 * and clears user-scoped HTTP caches (preserving the workbox precache).
 *
 * Callers are responsible for anything auth-store-specific (clearing the
 * in-memory user state or resetting the auth store) and for navigation
 * after teardown. Keeping the common teardown in one place means any
 * future offline-correctness fix (like the earlier cache-nuke removal)
 * only has to be made once.
 *
 * Uses dynamic imports to mirror the pattern in sessionExpired.ts and
 * avoid bringing the full store graph into any file that needs teardown.
 */
export async function teardownSession(): Promise<void> {
  const { poolPersistence } = await import('@/api/poolPersistence')
  poolPersistence.stopPersisting()

  const { useWebSocketStore } = await import('@/stores/websocket')
  useWebSocketStore().disconnect()

  const { useCommandQueueStore } = await import('@/stores/commandQueue')
  await useCommandQueueStore().reset()

  const { clearAll } = await import('@/api/poolDb')
  await clearAll()

  const { useObjectPoolStore } = await import('@/stores/objectPool')
  useObjectPoolStore().$reset()

  const { useWorkspaceStore } = await import('@/stores/workspace')
  useWorkspaceStore().$reset()

  localStorage.clear()

  const { clearUserCaches } = await import('@/api/clearUserCaches')
  await clearUserCaches()
}
