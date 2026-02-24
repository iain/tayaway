import { registerSW } from 'virtual:pwa-register'
import { useNotificationsStore } from '@/stores/notifications'

export function registerServiceWorker(): void {
  const updateSW = registerSW({
    immediate: true,
    onNeedRefresh() {
      const notifications = useNotificationsStore()
      notifications.showUpdate(
        'A new version is available. Click to reload.',
        () => updateSW(true)
      )
    },
  })
}
