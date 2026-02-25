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
          const keys = await caches.keys()
          await Promise.all(keys.map((k) => caches.delete(k)))
        }
        window.location.reload()
      })
    },
    onRegisteredSW(_url, registration) {
      if (!registration) return

      // Check for updates every 60 minutes
      setInterval(() => registration.update(), 60 * 60 * 1000)

      // Check for updates when tab becomes visible (throttled to 30s)
      let lastVisibilityCheck = 0
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState !== 'visible') return
        const now = Date.now()
        if (now - lastVisibilityCheck < 30_000) return
        lastVisibilityCheck = now
        registration.update()
      })
    },
  })
}
