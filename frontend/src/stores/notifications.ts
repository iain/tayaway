import { ref } from 'vue'
import { defineStore } from 'pinia'
import type { Notification } from '@/types/notification'

export const useNotificationsStore = defineStore('notifications', () => {
  const notifications = ref<Notification[]>([])

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

  function showInfo(
    message: string,
    options?: { action?: () => void; actionLabel?: string; duration?: number }
  ): string {
    const id = crypto.randomUUID()
    const notification: Notification = {
      id,
      type: 'info',
      message,
      action: options?.action,
      actionLabel: options?.actionLabel,
    }
    notifications.value.push(notification)

    setTimeout(() => {
      dismiss(id)
    }, options?.duration ?? 4000)

    return id
  }

  function dismiss(id: string): void {
    const index = notifications.value.findIndex((n) => n.id === id)
    if (index !== -1) {
      notifications.value.splice(index, 1)
    }
  }

  function $reset() {
    notifications.value = []
  }

  return {
    notifications,
    showError,
    showInfo,
    dismiss,
    $reset,
  }
})
