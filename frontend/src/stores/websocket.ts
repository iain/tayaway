import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { api } from '@/api/client'
import { useObjectPoolStore } from './objectPool'
import { useWorkspaceStore } from './workspace'
import type { PoolObject, ObjectType } from '@/types/pool'

type ConnectionState =
  | 'disconnected'
  | 'connecting'
  | 'connected'
  | 'authenticated'

interface DeletedObject {
  objectType: ObjectType
  id: string
}

interface BroadcastMessage {
  type: 'broadcast'
  workspaceId: string
  action: 'update' | 'delete'
  data: {
    objects?: PoolObject[]
    deleted?: DeletedObject[]
  }
}

interface SyncMessage {
  type: 'sync'
  data: {
    syncType?: 'full' | 'partial'
    syncedAt?: string
    objects: PoolObject[]
    deleted?: DeletedObject[]
  }
}

interface AuthenticatedMessage {
  type: 'authenticated'
  userId: string
  workspaceIds: string[]
  memberships: Array<{ workspaceId: string; memberId: string }>
}

interface ServerMessage {
  type: string
  workspaceId?: string
  action?: string
  data?: unknown
  userId?: string
  workspaceIds?: string[]
  message?: string
}

// Cascade relationship map: when an object is deleted, also remove its dependents
const CASCADE_RELATIONS: Partial<
  Record<ObjectType, { childType: ObjectType; foreignKey: string }[]>
> = {
  event: [{ childType: 'datePoll', foreignKey: 'eventId' }],
  datePoll: [{ childType: 'dateRange', foreignKey: 'datePollId' }],
  dateRange: [{ childType: 'vote', foreignKey: 'dateRangeId' }],
}

export const useWebSocketStore = defineStore('websocket', () => {
  const state = ref<ConnectionState>('disconnected')
  const workspaceIds = ref<string[]>([])
  const hasSynced = ref(false)
  const hasCachedData = ref(false)

  // Track last sync timestamp per workspace for partial sync
  const syncTimestamps = new Map<string, string>()

  let socket: WebSocket | null = null
  let reconnectTimeout: ReturnType<typeof setTimeout> | null = null
  let pingInterval: ReturnType<typeof setInterval> | null = null

  const isConnected = computed(() => state.value === 'authenticated')
  const isReconnecting = computed(
    () => hasSynced.value && state.value !== 'authenticated'
  )

  function getSyncedAt(workspaceId: string): string | undefined {
    return syncTimestamps.get(workspaceId)
  }

  function restoreSyncTimestamp(workspaceId: string, syncedAt: string): void {
    syncTimestamps.set(workspaceId, syncedAt)
  }

  async function getWebSocketUrl(): Promise<string> {
    const { data } = await api.post<{ ticket: string }>(
      '/auth/ws-ticket',
      undefined,
      { silent: true }
    )
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const host = window.location.host
    return `${protocol}//${host}/ws?ticket=${encodeURIComponent(data.ticket)}`
  }

  async function connect(): Promise<void> {
    // Don't connect if not authenticated (cookie-based, no token to check)
    const { useAuthStore } = await import('./auth')
    const authStore = useAuthStore()
    if (!authStore.isAuthenticated) return

    // If already connecting or connected, skip
    if (state.value !== 'disconnected') return

    state.value = 'connecting'

    try {
      const url = await getWebSocketUrl()
      socket = new WebSocket(url)

      socket.onopen = () => {}

      socket.onmessage = (event) => {
        handleMessage(event.data)
      }

      socket.onclose = () => {
        cleanup()
        scheduleReconnect()
      }

      socket.onerror = () => {
        // Error will trigger close event
      }
    } catch {
      state.value = 'disconnected'
      scheduleReconnect()
    }
  }

  function handleMessage(raw: string): void {
    let message: ServerMessage
    try {
      message = JSON.parse(raw) as ServerMessage
    } catch {
      console.warn('[WebSocket] Invalid JSON received')
      return
    }

    switch (message.type) {
      case 'authenticated':
        handleAuthenticated(message as unknown as AuthenticatedMessage)
        break
      case 'sync':
        handleSync(message as unknown as SyncMessage)
        break
      case 'broadcast':
        handleBroadcast(message as unknown as BroadcastMessage)
        break
      case 'pong':
        // Keep-alive response, nothing to do
        break
      case 'error':
        console.warn('[WebSocket] Server error:', message.message)
        break
    }
  }

  function handleAuthenticated(message: AuthenticatedMessage): void {
    state.value = 'authenticated'
    workspaceIds.value = message.workspaceIds

    // Set memberships on auth store
    import('./auth').then(({ useAuthStore }) => {
      const authStore = useAuthStore()
      const map = new Map<string, string>()
      for (const m of message.memberships ?? []) {
        map.set(m.workspaceId, m.memberId)
      }
      authStore.memberships = map
    })

    // Initialize workspace selection and request data for it
    const workspaceStore = useWorkspaceStore()
    workspaceStore.initialize(message.workspaceIds)
    if (workspaceStore.currentWorkspaceId) {
      const since = getSyncedAt(workspaceStore.currentWorkspaceId)
      send({
        type: 'switch_workspace',
        workspaceId: workspaceStore.currentWorkspaceId,
        since: since ?? null,
      })
    }

    // Start ping interval to keep connection alive
    pingInterval = setInterval(() => {
      send({ type: 'ping' })
    }, 30000)

    // Process any queued commands on reconnect
    import('./commandQueue').then(({ useCommandQueueStore }) => {
      const commandQueue = useCommandQueueStore()
      commandQueue.processQueue()
    })
  }

  function handleSync(message: SyncMessage): void {
    const pool = useObjectPoolStore()
    const workspaceStore = useWorkspaceStore()

    if (message.data?.syncType === 'full') {
      // Full sync: replace everything — server is authoritative
      if (message.data.objects) {
        pool.replaceObjects(message.data.objects)
      }
    } else if (message.data?.syncType === 'partial') {
      // Partial sync: import changed objects, remove deleted ones
      if (message.data.objects?.length) {
        pool.importObjects(message.data.objects)
      }
      if (message.data.deleted?.length) {
        for (const item of message.data.deleted) {
          cascadeRemove(pool, item.objectType, item.id)
        }
      }
    } else {
      // No syncType (e.g. workspace summaries): import without clearing
      if (message.data?.objects) {
        pool.importObjects(message.data.objects)
      }
    }

    // Store syncedAt for next partial sync
    if (message.data?.syncedAt && workspaceStore.currentWorkspaceId) {
      syncTimestamps.set(
        workspaceStore.currentWorkspaceId,
        message.data.syncedAt
      )
    }

    hasSynced.value = true
  }

  /** Remove an object and cascade-remove its dependents from the pool. */
  function cascadeRemove(
    pool: ReturnType<typeof useObjectPoolStore>,
    objectType: ObjectType,
    id: string
  ): void {
    // Find children before removing (need the object's data for FK lookups)
    const relations = CASCADE_RELATIONS[objectType]
    if (relations) {
      for (const rel of relations) {
        const children = pool
          .getAll(rel.childType)
          .filter(
            (obj) =>
              (obj as unknown as Record<string, string>)[rel.foreignKey] === id
          )
        for (const child of children) {
          cascadeRemove(pool, rel.childType, child.id)
        }
      }
    }
    pool.remove(objectType, id)
  }

  function handleBroadcast(message: BroadcastMessage): void {
    const pool = useObjectPoolStore()

    if (message.action === 'delete' && message.data?.deleted) {
      // Handle deletions from the deleted array
      for (const item of message.data.deleted) {
        cascadeRemove(pool, item.objectType, item.id)
      }
    } else if (message.action === 'update' && message.data?.objects) {
      pool.importObjects(message.data.objects)
    }
  }

  function sendSwitchWorkspace(workspaceId: string): void {
    hasSynced.value = false
    hasCachedData.value = false
    const since = getSyncedAt(workspaceId)
    send({ type: 'switch_workspace', workspaceId, since: since ?? null })
  }

  function send(data: object): void {
    if (socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(data))
    }
  }

  function cleanup(): void {
    if (pingInterval) {
      clearInterval(pingInterval)
      pingInterval = null
    }

    socket = null
    state.value = 'disconnected'
  }

  function scheduleReconnect(): void {
    const delay = 1000

    reconnectTimeout = setTimeout(async () => {
      // Don't reconnect if logged out — dynamic import avoids circular deps
      const { useAuthStore } = await import('./auth')
      const authStore = useAuthStore()
      if (!authStore.isAuthenticated) return

      connect()
    }, delay)
  }

  function reconnect(): void {
    // Cancel any pending reconnect
    if (reconnectTimeout) {
      clearTimeout(reconnectTimeout)
      reconnectTimeout = null
    }

    // Clean up ping interval
    if (pingInterval) {
      clearInterval(pingInterval)
      pingInterval = null
    }

    // Close existing socket without triggering scheduleReconnect
    if (socket) {
      socket.onclose = null
      socket.close()
      socket = null
    }

    state.value = 'disconnected'

    connect()
  }

  // Reconnect immediately when browser comes back online
  window.addEventListener('online', () => {
    if (state.value !== 'authenticated') {
      reconnect()
    }
  })

  function disconnect(): void {
    if (reconnectTimeout) {
      clearTimeout(reconnectTimeout)
      reconnectTimeout = null
    }

    if (pingInterval) {
      clearInterval(pingInterval)
      pingInterval = null
    }

    if (socket) {
      socket.onclose = null // Prevent reconnect
      socket.close()
      socket = null
    }

    workspaceIds.value = []
    state.value = 'disconnected'
    hasSynced.value = false
    hasCachedData.value = false
  }

  function $reset(): void {
    disconnect()
    syncTimestamps.clear()
  }

  // Deprecated - kept for backwards compatibility during migration
  // These are now no-ops since subscriptions are automatic based on workspace membership
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  function subscribe(channel: string): void {
    // No-op: subscriptions are now automatic based on workspace membership
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  function unsubscribe(channel: string): void {
    // No-op: subscriptions are now automatic based on workspace membership
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  function subscribeToEvent(eventId: string): void {
    // No-op: subscriptions are now automatic based on workspace membership
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  function unsubscribeFromEvent(eventId: string): void {
    // No-op: subscriptions are now automatic based on workspace membership
  }

  return {
    state,
    workspaceIds,
    isConnected,
    isReconnecting,
    hasSynced,
    hasCachedData,
    connect,
    reconnect,
    disconnect,
    sendSwitchWorkspace,
    getSyncedAt,
    restoreSyncTimestamp,
    // Deprecated - kept for backwards compatibility
    subscribe,
    unsubscribe,
    subscribeToEvent,
    unsubscribeFromEvent,
    $reset,
  }
})
