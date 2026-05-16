import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { rawApi } from '@/api/client'
import { useNotificationsStore } from '@/stores/notifications'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useWorkspaceStore } from '@/stores/workspace'
import { Scope } from '@/api/scope'
import type { PoolNotification } from '@/types/pool'

const SILENCE_UNDO_MS = 5000

const SILENCE_FAILURE_MESSAGE =
  "Couldn't update. Try again from notification settings."

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

  // Unread counts for workspaces *other than* the one the user is currently
  // in. The current workspace's notifications surface in the bell directly,
  // so the selector dot is only meaningful elsewhere. Filtering here keeps
  // callers from having to remember the exclusion.
  //
  // notification.workspaceId is nullable (no NOT NULL on the column) —
  // workspace-less notifications can't badge any selector entry, so we
  // skip them outright.
  const unreadCountByOtherWorkspace = computed(() => {
    const workspaceStore = useWorkspaceStore()
    const currentId = workspaceStore.currentWorkspaceId
    const counts = new Map<string, number>()
    for (const n of unread.value) {
      if (!n.workspaceId || n.workspaceId === currentId) continue
      counts.set(n.workspaceId, (counts.get(n.workspaceId) ?? 0) + 1)
    }
    return counts
  })

  async function load(): Promise<void> {
    loading.value = true
    lastError.value = null
    try {
      const { data } = await rawApi.get<InboxResponse>('/notifications', {})
      // Notifications live in the personal scope — they're delivered to the
      // user across all workspaces.
      pool().importObjects(data.objects, { scope: Scope.personal() })
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
    // No scope arg — the pool keeps the notification in whatever scope it's
    // already in (personal, from the handshake).
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

  // "Stop sending me these" from a bell row. Persists the silence
  // immediately so the preference survives the user closing the tab or
  // navigating away inside the undo window. The toast's Undo action POSTs
  // unsilence to clear the override rows and restore defaults. Keeps the
  // bell as the everyday control surface promised by the design (settings
  // is rare-visit).
  function silenceKind(
    kind: string,
    message: string,
    notificationId?: string
  ): void {
    const toast = useNotificationsStore()

    if (notificationId) void markRead(notificationId)

    void rawApi
      .post('/notifications/preferences/silence', { kind }, { silent: true })
      .catch(() => {
        toast.showError(SILENCE_FAILURE_MESSAGE)
      })

    toast.showInfo(message, {
      actionLabel: 'Undo',
      action: () => {
        void rawApi
          .post(
            '/notifications/preferences/unsilence',
            { kind },
            { silent: true }
          )
          .catch(() => {
            toast.showError(SILENCE_FAILURE_MESSAGE)
          })
      },
      duration: SILENCE_UNDO_MS,
    })
  }

  return {
    notifications,
    unread,
    unreadCount,
    unreadCountByOtherWorkspace,
    loading,
    lastError,
    load,
    markRead,
    markAllRead,
    silenceKind,
  }
})
