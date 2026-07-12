import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { rawApi } from '@/api/client'
import { checkForServiceWorkerUpdate } from '@/api/swUpdate'
import { useObjectPoolStore } from './objectPool'
import { useWorkspaceStore, WORKSPACE_ID_STORAGE_KEY } from './workspace'
import { Scope } from '@/api/scope'
import type { PoolObject } from '@/types/pool'
import type { DeletedObject } from '@/types/poolUpdate'

type ConnectionState =
  | 'disconnected'
  | 'connecting'
  | 'connected'
  | 'authenticated'

interface BroadcastMessage {
  type: 'broadcast'
  // Workspace-audience broadcasts carry workspaceId; user-audience ones omit
  // it (the connection itself is the audience identifier).
  workspaceId?: string
  action: 'update' | 'delete'
  data: {
    objects?: PoolObject[]
    deleted?: DeletedObject[]
  }
}

interface SyncMessage {
  type: 'sync'
  data: {
    syncType?: 'full' | 'partial' | 'personal'
    syncedAt?: string
    // The workspace this sync is for, tagged by the server. Absent on
    // personal syncs (and on payloads from servers that predate the tag).
    workspaceId?: string
    objects: PoolObject[]
    deleted?: DeletedObject[]
  }
}

interface AuthenticatedMessage {
  type: 'authenticated'
  userId: string
  workspaceIds: string[]
  initialWorkspaceId?: string
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

export const useWebSocketStore = defineStore('websocket', () => {
  const state = ref<ConnectionState>('disconnected')
  const workspaceIds = ref<string[]>([])
  const hasSynced = ref(false)
  const hasCachedData = ref(false)
  // Set to true when ticket fetch fails so the loading screen exits and the
  // connection badge becomes visible even before a first successful sync.
  const connectionFailed = ref(false)

  // Track last sync timestamp per workspace for partial sync
  const syncTimestamps = new Map<string, string>()
  // Last *full* sync per workspace. A full sync is the only authoritative
  // repair for drift — missed broadcasts, lost tombstones, leftover zombies
  // — so partial syncs are only trusted while the last full sync is fresh.
  const fullSyncTimestamps = new Map<string, string>()

  // How long a client may go without a full-sync reconciliation. Jitter
  // spreads the resulting full syncs so a deploy that reconnects every
  // client doesn't stampede the server with them.
  const FULL_SYNC_INTERVAL_MS = 24 * 60 * 60 * 1000
  const FULL_SYNC_JITTER_MS = 2 * 60 * 60 * 1000

  // The `since` to put on the next sync request for a workspace: the
  // partial-sync cursor while the last full sync is fresh, or null to
  // request a full sync once the reconciliation interval has passed (or no
  // full sync was ever recorded).
  function reconcileCursor(workspaceId: string): string | null {
    const since = syncTimestamps.get(workspaceId)
    if (!since) return null
    const lastFull = fullSyncTimestamps.get(workspaceId)
    if (!lastFull) return null
    const interval = FULL_SYNC_INTERVAL_MS - Math.random() * FULL_SYNC_JITTER_MS
    if (Date.now() - new Date(lastFull).getTime() >= interval) return null
    return since
  }

  let socket: WebSocket | null = null
  let reconnectTimeout: ReturnType<typeof setTimeout> | null = null
  let pingInterval: ReturnType<typeof setInterval> | null = null
  // Armed after each ping; cleared on the corresponding pong. If it fires,
  // the connection is half-open (server dead, TCP RST lost, mobile tower
  // handoff, etc.) and we force a reconnect.
  let pongTimeout: ReturnType<typeof setTimeout> | null = null
  const PONG_TIMEOUT_MS = 10000
  let reconnectAttempts = 0
  const gitSha = ref<string | null>(null)

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

  function getFullSyncedAt(workspaceId: string): string | undefined {
    return fullSyncTimestamps.get(workspaceId)
  }

  function restoreFullSyncTimestamp(
    workspaceId: string,
    syncedAt: string
  ): void {
    fullSyncTimestamps.set(workspaceId, syncedAt)
  }

  async function getWebSocketUrl(): Promise<string> {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), 5000)
    let data: { ticket: string }
    try {
      const result = await rawApi.post<{ ticket: string }>(
        '/auth/ws-ticket',
        undefined,
        { silent: true, signal: controller.signal }
      )
      data = result.data
    } catch (e) {
      state.value = 'disconnected'
      throw e
    } finally {
      clearTimeout(timeout)
    }
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const host = window.location.host
    let url = `${protocol}//${host}/ws?ticket=${encodeURIComponent(data.ticket)}`

    // Include current workspace so the server can sync it immediately.
    // The cursor comes from reconcileCursor: partial while the last full
    // sync is fresh, full otherwise. On cold starts the in-memory cursors
    // were restored by loadFromCache — App.vue connects only after
    // hydration, so a cursor here implies its cached baseline loaded.
    const storedWorkspaceId = localStorage.getItem(WORKSPACE_ID_STORAGE_KEY)
    if (storedWorkspaceId) {
      url += `&workspaceId=${encodeURIComponent(storedWorkspaceId)}`
      const since = reconcileCursor(storedWorkspaceId)
      if (since) {
        url += `&since=${encodeURIComponent(since)}`
      }
    }

    return url
  }

  async function connect(): Promise<void> {
    // Don't connect if not authenticated (cookie-based, no token to check)
    const { useAuthStore } = await import('./auth')
    const authStore = useAuthStore()
    if (!authStore.isAuthenticated) return

    // If already connecting or connected, skip
    if (state.value !== 'disconnected') return

    connectionFailed.value = false
    state.value = 'connecting'
    connectionFailed.value = false

    // Register online + visibility listeners for this connection attempt.
    // removeEventListener before adding ensures idempotency across reconnect cycles.
    window.removeEventListener('online', onOnline)
    window.addEventListener('online', onOnline)
    document.removeEventListener('visibilitychange', onVisibilityChange)
    document.addEventListener('visibilitychange', onVisibilityChange)

    try {
      const url = await getWebSocketUrl()
      socket = new WebSocket(url)

      socket.onopen = () => {
        // Strip the ticket from the URL before logging to avoid leaking the JWT
        const safeUrl = url.replace(/ticket=[^&]+/, 'ticket=<redacted>')
        console.info('[WebSocket] Connected to', safeUrl)
      }

      socket.onmessage = (event) => {
        handleMessage(event.data)
      }

      socket.onclose = (event) => {
        console.warn(
          `[WebSocket] Closed — code: ${event.code}, reason: ${event.reason || '(none)'}, reconnect attempt: ${reconnectAttempts + 1}`
        )
        cleanup()
        scheduleReconnect()
      }

      socket.onerror = (event) => {
        console.warn('[WebSocket] Error', event)
        // Reset state so the close handler (or reconnect logic) can proceed.
        // Without this, a socket error without a close event leaves state stuck.
        if (state.value === 'authenticated' || state.value === 'connecting') {
          state.value = 'disconnected'
        }
      }
    } catch (e) {
      state.value = 'disconnected'
      // 401 from ws-ticket means session expired — the API client
      // triggers handleSessionExpired, so just bail out here
      if (
        typeof e === 'object' &&
        e !== null &&
        'status' in e &&
        (e as { status: number }).status === 401
      ) {
        return
      }
      // Surface the failure: exit the loading screen so the connection badge
      // is visible even when hasSynced and hasCachedData are both false.
      console.warn('[WebSocket] Ticket fetch failed', e)
      connectionFailed.value = true
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
        handlePong(message as unknown as { type: 'pong'; gitSha?: string })
        break
      case 'session_revoked':
        handleSessionRevoked()
        break
      case 'error':
        console.warn('[WebSocket] Server error:', message.message)
        break
    }
  }

  function handlePong(message: { type: 'pong'; gitSha?: string }): void {
    // Server is alive — clear any armed pong timeout before doing anything
    // else, so a slow gitSha handler can't accidentally let the timeout fire.
    if (pongTimeout !== null) {
      clearTimeout(pongTimeout)
      pongTimeout = null
    }
    if (!message.gitSha) return
    const previous = gitSha.value
    gitSha.value = message.gitSha
    if (previous !== null && previous !== message.gitSha) {
      // Server reports a different git SHA — there's a fresh deploy. Trigger
      // an immediate service worker update check; the standard onNeedRefresh
      // flow in registerSW.ts schedules the auto-update once the new SW
      // finishes installing.
      void checkForServiceWorkerUpdate()
    }
  }

  async function handleSessionRevoked(): Promise<void> {
    console.warn('[WebSocket] Session revoked by another device')
    const { handleSessionExpired } = await import('@/api/sessionExpired')
    await handleSessionExpired()
  }

  function handleAuthenticated(message: AuthenticatedMessage): void {
    state.value = 'authenticated'
    reconnectAttempts = 0
    gitSha.value = null
    workspaceIds.value = message.workspaceIds

    // No workspaces → no workspace sync will ever arrive; the personal
    // sync is all there is, so don't hold the loading screen for more.
    if (message.workspaceIds.length === 0) {
      hasSynced.value = true
    }

    // Initialize workspace selection and request data for it
    const workspaceStore = useWorkspaceStore()
    workspaceStore.initialize(message.workspaceIds)
    if (workspaceStore.currentWorkspaceId) {
      // Only send switch_workspace if the server didn't already sync this workspace
      if (message.initialWorkspaceId !== workspaceStore.currentWorkspaceId) {
        const since = getSyncedAt(workspaceStore.currentWorkspaceId)
        send({
          type: 'switch_workspace',
          workspaceId: workspaceStore.currentWorkspaceId,
          since: since ?? null,
        })
      }
    }

    // Start ping interval to keep connection alive. Arm a pong timeout on
    // each ping so we detect half-open connections where the server is dead
    // but the browser still thinks the socket is OPEN.
    pingInterval = setInterval(sendPingWithWatchdog, 30000)

    // Process any queued commands on reconnect
    import('./commandQueue').then(({ useCommandQueueStore }) => {
      const commandQueue = useCommandQueueStore()
      commandQueue.processQueue()
    })
  }

  function handleSync(message: SyncMessage): void {
    const pool = useObjectPoolStore()
    const workspaceStore = useWorkspaceStore()

    // Personal syncs land in Scope.personal(); workspace syncs land in the
    // scope of the workspace the server tagged on the payload. Routing by
    // "current workspace at receive time" instead would misroute syncs that
    // land mid-switch or via the new-member bootstrap — and a misrouted
    // *full* sync replaces the wrong scope, wiping the workspace the user
    // is looking at. The current workspace is only a fallback for servers
    // that don't tag the payload yet.
    const isPersonal = message.data?.syncType === 'personal'
    const syncWorkspaceId =
      message.data?.workspaceId ?? workspaceStore.currentWorkspaceId
    const scope = isPersonal
      ? Scope.personal()
      : syncWorkspaceId
        ? Scope.workspace(syncWorkspaceId)
        : null
    if (!scope) return

    // Stamp cursors before applying: the persistence layer reads them when
    // the replace/import events fire, and syncedAt was captured server-side
    // before the query, so it is a valid cursor regardless of apply timing.
    if (message.data?.syncedAt && !isPersonal && syncWorkspaceId) {
      syncTimestamps.set(syncWorkspaceId, message.data.syncedAt)
      if (message.data.syncType === 'full') {
        fullSyncTimestamps.set(syncWorkspaceId, message.data.syncedAt)
      }
    }

    if (message.data?.syncType === 'full') {
      pool.applyUpdate(scope, {
        kind: 'replace',
        objects: message.data.objects ?? [],
      })
    } else {
      pool.applyUpdate(scope, {
        kind: 'merge',
        objects: message.data?.objects,
        deleted: message.data?.deleted,
      })
    }

    // The personal sync is a small always-first payload; flipping hasSynced
    // on it aborted workspace cache hydration and skipped restoring pending
    // overlays. Only a workspace sync means "the workspace has synced".
    if (!isPersonal) {
      hasSynced.value = true
    }
  }

  function handleBroadcast(message: BroadcastMessage): void {
    const pool = useObjectPoolStore()
    // Workspace-audience broadcasts carry workspaceId on the envelope; user-
    // audience ones don't and land in the personal scope.
    const scope = message.workspaceId
      ? Scope.workspace(message.workspaceId)
      : Scope.personal()
    pool.applyUpdate(scope, {
      kind: 'merge',
      objects: message.action === 'update' ? message.data?.objects : undefined,
      deleted: message.action === 'delete' ? message.data?.deleted : undefined,
    })
  }

  function sendSwitchWorkspace(workspaceId: string): void {
    hasSynced.value = false
    // hasCachedData stays as-is — it gates the full-page loader, not per-
    // route loading. Personal data (workspace selector, own memberships,
    // notifications) is still in the pool, so the layout should keep
    // rendering during the switch; route-level skeletons handle the empty
    // new-workspace view until the sync arrives.
    send({
      type: 'switch_workspace',
      workspaceId,
      since: reconcileCursor(workspaceId),
    })
  }

  function send(data: object): void {
    if (socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(data))
    }
  }

  function sendPingWithWatchdog(): void {
    send({ type: 'ping' })
    if (pongTimeout !== null) clearTimeout(pongTimeout)
    pongTimeout = setTimeout(() => {
      console.warn(
        '[WebSocket] Pong timeout — connection looks half-open, reconnecting'
      )
      pongTimeout = null
      reconnect()
    }, PONG_TIMEOUT_MS)
  }

  function cleanup(): void {
    if (pingInterval) {
      clearInterval(pingInterval)
      pingInterval = null
    }
    if (pongTimeout !== null) {
      clearTimeout(pongTimeout)
      pongTimeout = null
    }

    socket = null
    state.value = 'disconnected'
  }

  function scheduleReconnect(): void {
    const baseDelay = Math.min(1000 * Math.pow(2, reconnectAttempts), 30000)
    const jitter = Math.random() * 1000
    const delay = baseDelay + jitter
    // Cap the counter so it doesn't grow unbounded during long offline
    // stretches. The delay itself is already saturated well before this.
    reconnectAttempts = Math.min(reconnectAttempts + 1, 32)
    console.info(
      `[WebSocket] Reconnect attempt ${reconnectAttempts} scheduled in ${Math.round(delay)}ms`
    )

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

    // Clean up ping interval and pong watchdog
    if (pingInterval) {
      clearInterval(pingInterval)
      pingInterval = null
    }
    if (pongTimeout !== null) {
      clearTimeout(pongTimeout)
      pongTimeout = null
    }

    // Close existing socket without triggering scheduleReconnect
    if (socket) {
      socket.onclose = null
      socket.close()
      socket = null
    }

    state.value = 'disconnected'
    reconnectAttempts = 0

    connect()
  }

  // Named ref so removeEventListener can target it exactly.
  // Registered in connect() and removed in disconnect().
  const onOnline = (): void => {
    if (state.value !== 'authenticated') {
      reconnect()
    }
  }

  // Throttle for the visibility reconciliation below — visibility flips
  // constantly on mobile, and each request costs the server a changed_since
  // pass over every type.
  const VISIBILITY_RECONCILE_MIN_INTERVAL_MS = 60_000
  let lastVisibilityReconcileAt = 0

  // A tab that was frozen or throttled in the background may resume on a
  // socket the server has already pruned (or that died without an onclose).
  // Probe liveness immediately instead of waiting up to 30s for the next
  // interval tick — the pong watchdog (or the server closing an
  // unregistered connection) then forces a reconnect within seconds.
  //
  // Also request a reconciliation sync for the current workspace: NOTIFYs
  // lost server-side (LISTEN reconnects) leave connected clients silently
  // stale with nothing else to catch them up. switch_workspace is just
  // "send me a sync" server-side — no subscription change.
  const onVisibilityChange = (): void => {
    if (document.visibilityState !== 'visible') return
    if (state.value !== 'authenticated') return
    sendPingWithWatchdog()

    const now = Date.now()
    if (now - lastVisibilityReconcileAt < VISIBILITY_RECONCILE_MIN_INTERVAL_MS)
      return
    const wsId = useWorkspaceStore().currentWorkspaceId
    if (!wsId) return
    lastVisibilityReconcileAt = now
    send({
      type: 'switch_workspace',
      workspaceId: wsId,
      since: reconcileCursor(wsId),
    })
  }

  function disconnect(): void {
    window.removeEventListener('online', onOnline)
    document.removeEventListener('visibilitychange', onVisibilityChange)

    if (reconnectTimeout) {
      clearTimeout(reconnectTimeout)
      reconnectTimeout = null
    }

    if (pingInterval) {
      clearInterval(pingInterval)
      pingInterval = null
    }
    if (pongTimeout !== null) {
      clearTimeout(pongTimeout)
      pongTimeout = null
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
    connectionFailed.value = false
  }

  function $reset(): void {
    disconnect()
    syncTimestamps.clear()
    fullSyncTimestamps.clear()
    lastVisibilityReconcileAt = 0
  }

  return {
    state,
    workspaceIds,
    isConnected,
    isReconnecting,
    hasSynced,
    hasCachedData,
    connectionFailed,
    gitSha,
    connect,
    reconnect,
    disconnect,
    sendSwitchWorkspace,
    getSyncedAt,
    restoreSyncTimestamp,
    getFullSyncedAt,
    restoreFullSyncTimestamp,
    $reset,
  }
})
