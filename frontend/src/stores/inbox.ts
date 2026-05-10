import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { rawApi } from '@/api/client'
import { useNotificationsStore } from '@/stores/notifications'
import { useObjectPoolStore } from '@/stores/objectPool'
import type { PoolNotification } from '@/types/pool'

const SILENCE_UNDO_MS = 5000

// Re-exported under the original name so the bell component (and any other
// consumers) keeps a single import surface as we move from a parallel array
// to the shared object pool.
export type InboxNotification = PoolNotification

interface InboxResponse {
  objects: PoolNotification[]
}

/**
 * Persistent in-app notification inbox. Distinct from `useNotificationsStore`
 * (transient toasts) — this one backs the bell icon and the user's history.
 *
 * Notifications live in the shared object pool, which is the same place
 * real-time WebSocket broadcasts land. The store is a thin reactive view
 * over that pool plus the mutation paths (mark read, silence) that don't
 * fit the optimistic-mutation queue.
 */
export const useInboxStore = defineStore('inbox', () => {
  const loading = ref(false)
  const lastError = ref<string | null>(null)

  function pool() {
    return useObjectPoolStore()
  }

  const notifications = computed<PoolNotification[]>(() => {
    const all = pool().getAll('notification')
    return [...all].sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1))
  })

  const unread = computed(() =>
    notifications.value.filter((n) => n.readAt === null)
  )

  const unreadCount = computed(() => unread.value.length)

  async function load(): Promise<void> {
    loading.value = true
    lastError.value = null
    try {
      const { data } = await rawApi.get<InboxResponse>('/notifications', {})
      pool().importObjects(data.objects)
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
    const target = pool().get('notification', id)
    if (!target || target.readAt !== null) return

    const previous = target
    pool().set({ ...target, readAt: new Date().toISOString() })

    try {
      await rawApi.put(`/notifications/${id}/read`, {}, { silent: true })
    } catch {
      pool().set(previous)
    }
  }

  async function markAllRead(): Promise<void> {
    const before = pool()
      .getAll('notification')
      .filter((n) => n.readAt === null)
    if (before.length === 0) return

    const now = new Date().toISOString()
    for (const n of before) {
      pool().set({ ...n, readAt: now })
    }

    try {
      await rawApi.put('/notifications/read-all', {}, { silent: true })
    } catch {
      for (const n of before) {
        pool().set(n)
      }
    }
  }

  // "Stop sending me these" from a bell row. Optimistically marks the
  // current notification read, shows an undo toast, and only fires the
  // POST after the undo window expires. If the user undoes it, nothing
  // ever hits the server. Keeps the bell as the everyday control surface
  // promised by the design (settings is rare-visit).
  function silenceKind(
    kind: string,
    message: string,
    notificationId?: string
  ): void {
    const toast = useNotificationsStore()

    if (notificationId) void markRead(notificationId)

    let undone = false
    toast.showInfo(message, {
      actionLabel: 'Undo',
      action: () => {
        undone = true
      },
      duration: SILENCE_UNDO_MS,
    })

    setTimeout(async () => {
      if (undone) return
      try {
        await rawApi.post(
          '/notifications/preferences/silence',
          { kind },
          { silent: true }
        )
      } catch {
        toast.showError(
          "Couldn't update. Try again from notification settings."
        )
      }
    }, SILENCE_UNDO_MS)
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
    silenceKind,
  }
})
