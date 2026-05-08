import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { rawApi } from '@/api/client'

export interface InboxNotification {
  id: string
  objectType: 'notification'
  userId: string
  workspaceId: string | null
  kind: string
  data: {
    title?: string
    body?: string
    href?: string
    [key: string]: unknown
  }
  readAt: string | null
  createdAt: string
  updatedAt: string
}

interface InboxResponse {
  notifications: InboxNotification[]
  unreadCount: number
}

/**
 * Persistent in-app notification inbox. Distinct from `useNotificationsStore`
 * (transient toasts) — this one backs the bell icon and the user's history.
 *
 * Loads via REST today; live websocket sync can be added without changing
 * this store's shape since notifications would just arrive through the
 * same `notifications` array.
 */
export const useInboxStore = defineStore('inbox', () => {
  const notifications = ref<InboxNotification[]>([])
  const unreadCount = ref(0)
  const loading = ref(false)
  const lastError = ref<string | null>(null)

  const unread = computed(() =>
    notifications.value.filter((n) => n.readAt === null)
  )

  async function load(): Promise<void> {
    loading.value = true
    lastError.value = null
    try {
      const { data } = await rawApi.get<InboxResponse>('/notifications', {})
      notifications.value = data.notifications
      unreadCount.value = data.unreadCount
    } catch (e) {
      lastError.value =
        e && typeof e === 'object' && 'message' in e
          ? String((e as { message: unknown }).message)
          : 'load failed'
    } finally {
      loading.value = false
    }
  }

  async function markRead(id: string): Promise<void> {
    const target = notifications.value.find((n) => n.id === id)
    if (!target || target.readAt !== null) return

    const previousReadAt = target.readAt
    target.readAt = new Date().toISOString()
    if (unreadCount.value > 0) unreadCount.value -= 1

    try {
      await rawApi.put(`/notifications/${id}/read`, {}, { silent: true })
    } catch {
      target.readAt = previousReadAt
      unreadCount.value += 1
    }
  }

  async function markAllRead(): Promise<void> {
    const previously = notifications.value.map((n) => ({
      id: n.id,
      readAt: n.readAt,
    }))
    const previousCount = unreadCount.value
    const now = new Date().toISOString()

    notifications.value.forEach((n) => {
      if (n.readAt === null) n.readAt = now
    })
    unreadCount.value = 0

    try {
      await rawApi.put('/notifications/read-all', {}, { silent: true })
    } catch {
      previously.forEach((p) => {
        const target = notifications.value.find((n) => n.id === p.id)
        if (target) target.readAt = p.readAt
      })
      unreadCount.value = previousCount
    }
  }

  return {
    notifications,
    unread,
    unreadCount,
    loading,
    lastError,
    load,
    markRead,
    markAllRead,
  }
})
