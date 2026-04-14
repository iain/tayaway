import { registerSW } from 'virtual:pwa-register'
import { useNotificationsStore } from '@/stores/notifications'

export function registerServiceWorker(): void {
  void requestPersistentStorage()

  const updateSW = registerSW({
    immediate: true,
    onNeedRefresh() {
      const notifications = useNotificationsStore()
      notifications.showUpdate(async () => {
        try {
          await updateSW(true)
        } catch {
          // SW update failed — fall through to manual reload
        }

        window.location.reload()
      })
    },
    onRegisteredSW(_url, registration) {
      if (!registration) return

      const onUpdateError = (err: unknown) =>
        console.warn('SW update failed:', err)

      // Check for updates every 60 minutes
      setInterval(
        () => registration.update().catch(onUpdateError),
        60 * 60 * 1000
      )

      // Check for updates when tab becomes visible (throttled to 30s)
      let lastVisibilityCheck = 0
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState !== 'visible') return
        const now = Date.now()
        if (now - lastVisibilityCheck < 30_000) return
        lastVisibilityCheck = now
        registration.update().catch(onUpdateError)
      })
    },
  })
}

// Re-export so existing consumers (and docs pointing at registerSW.ts) keep
// working. The real definition lives in @/api/swUpdate so it can be imported
// without dragging `virtual:pwa-register` into the module graph.
export { checkForServiceWorkerUpdate } from '@/api/swUpdate'

// Ask the browser to keep our IndexedDB and Cache Storage from being evicted
// under storage pressure or extended inactivity. Without this, iOS evicts PWA
// storage after ~7 days of disuse, wiping the precache and pool cache. We
// check persisted() first so repeat page loads don't ask again once the
// origin has already been granted persistent storage.
async function requestPersistentStorage(): Promise<void> {
  if (!navigator.storage?.persist) return
  try {
    if (await navigator.storage.persisted?.()) return
    await navigator.storage.persist()
  } catch {
    // Non-critical
  }
}
