import { ref } from 'vue'
import type { Notification } from '@/types/notification'

const notifications = ref<Notification[]>([])

export function useNotifications() {
  function showError(message: string): void {
    const id = crypto.randomUUID()
    const notification: Notification = {
      id,
      type: 'error',
      message,
    }
    notifications.value.push(notification)

    setTimeout(() => {
      dismiss(id)
    }, 5000)
  }

  function dismiss(id: string): void {
    const index = notifications.value.findIndex((n) => n.id === id)
    if (index !== -1) {
      notifications.value.splice(index, 1)
    }
  }

  return {
    notifications,
    showError,
    dismiss,
  }
}
