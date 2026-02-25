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

  function showInfo(message: string): void {
    const id = crypto.randomUUID()
    const notification: Notification = {
      id,
      type: 'info',
      message,
    }
    notifications.value.push(notification)

    setTimeout(() => {
      dismiss(id)
    }, 4000)
  }

  function showUpdate(action: () => void): void {
    if (notifications.value.some((n) => n.type === 'update')) return
    const id = crypto.randomUUID()
    const notification: Notification = {
      id,
      type: 'update',
      message: 'A new version is available. Click to reload.',
      action,
    }
    notifications.value.push(notification)
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
    showUpdate,
    dismiss,
    $reset,
  }
})
