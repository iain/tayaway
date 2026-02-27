import { registerSW } from 'virtual:pwa-register'
import { useNotificationsStore } from '@/stores/notifications'

export function registerServiceWorker(): void {
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

        // Always clear caches before reloading. On iOS standalone PWA,
        // skipWaiting() can silently fail, leaving the old SW active.
        // Clearing caches ensures reload fetches fresh content regardless.
        try {
          const keys = await caches.keys()
          await Promise.all(keys.map((k) => caches.delete(k)))
        } catch {
          // Cache API unavailable
        }

        window.location.reload()
      })
    },
    onRegisteredSW(_url, registration) {
      if (!registration) return

      // Check for updates every 60 minutes
      setInterval(() => registration.update().catch(() => {}), 60 * 60 * 1000)

      // Check for updates when tab becomes visible (throttled to 30s)
      let lastVisibilityCheck = 0
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState !== 'visible') return
        const now = Date.now()
        if (now - lastVisibilityCheck < 30_000) return
        lastVisibilityCheck = now
        registration.update().catch(() => {})
      })
    },
  })
}
