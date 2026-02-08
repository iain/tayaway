import { ref, computed } from "vue"
import { defineStore } from "pinia"
import { getSessionToken } from "@/api/client"
import { useObjectPoolStore } from "./objectPool"
import type { PoolObject, ObjectType } from "@/types/pool"

type ConnectionState = "disconnected" | "connecting" | "connected" | "authenticated"

interface DeletedObject {
  objectType: ObjectType
  id: string
}

interface BroadcastMessage {
  type: "broadcast"
  workspaceId: string
  action: "update" | "delete"
  data: {
    objects?: PoolObject[]
    deleted?: DeletedObject[]
  }
}

interface SyncMessage {
  type: "sync"
  data: {
    objects: PoolObject[]
  }
}

interface AuthenticatedMessage {
  type: "authenticated"
  userId: string
  workspaceIds: string[]
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

export const useWebSocketStore = defineStore("websocket", () => {
  const state = ref<ConnectionState>("disconnected")
  const workspaceIds = ref<string[]>([])
  const hasSynced = ref(false)

  let socket: WebSocket | null = null
  let reconnectAttempts = 0
  let reconnectTimeout: ReturnType<typeof setTimeout> | null = null
  let pingInterval: ReturnType<typeof setInterval> | null = null

  const isConnected = computed(() => state.value === "authenticated")

  function getWebSocketUrl(): string {
    const token = getSessionToken()
    if (!token) throw new Error("No session token available")

    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
    const host = window.location.host
    return `${protocol}//${host}/ws?token=${encodeURIComponent(token)}`
  }

  function connect(): void {
    if (state.value !== "disconnected") return

    const token = getSessionToken()
    if (!token) return

    state.value = "connecting"

    try {
      socket = new WebSocket(getWebSocketUrl())

      socket.onopen = () => {
        reconnectAttempts = 0
      }

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
      state.value = "disconnected"
      scheduleReconnect()
    }
  }

  function handleMessage(raw: string): void {
    let message: ServerMessage
    try {
      message = JSON.parse(raw) as ServerMessage
    } catch {
      console.warn("[WebSocket] Invalid JSON received")
      return
    }

    switch (message.type) {
      case "authenticated":
        handleAuthenticated(message as unknown as AuthenticatedMessage)
        break
      case "sync":
        handleSync(message as unknown as SyncMessage)
        break
      case "broadcast":
        handleBroadcast(message as unknown as BroadcastMessage)
        break
      case "pong":
        // Keep-alive response, nothing to do
        break
      case "error":
        console.warn("[WebSocket] Server error:", message.message)
        break
    }
  }

  function handleAuthenticated(message: AuthenticatedMessage): void {
    state.value = "authenticated"
    workspaceIds.value = message.workspaceIds

    // Start ping interval to keep connection alive
    pingInterval = setInterval(() => {
      send({ type: "ping" })
    }, 30000)
  }

  function handleSync(message: SyncMessage): void {
    const pool = useObjectPoolStore()
    if (message.data?.objects) {
      pool.importObjects(message.data.objects)
    }
    hasSynced.value = true
  }

  function handleBroadcast(message: BroadcastMessage): void {
    const pool = useObjectPoolStore()

    if (message.action === "delete" && message.data?.deleted) {
      // Handle deletions from the deleted array
      for (const item of message.data.deleted) {
        pool.remove(item.objectType, item.id)
      }
    } else if (message.action === "update" && message.data?.objects) {
      pool.importObjects(message.data.objects)
    }
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
    state.value = "disconnected"
    hasSynced.value = false
  }

  function scheduleReconnect(): void {
    const token = getSessionToken()
    if (!token) return // Don't reconnect if logged out

    const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), 30000)
    reconnectAttempts++

    reconnectTimeout = setTimeout(() => {
      connect()
    }, delay)
  }

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
    state.value = "disconnected"
    reconnectAttempts = 0
  }

  function $reset(): void {
    disconnect()
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
    hasSynced,
    connect,
    disconnect,
    // Deprecated - kept for backwards compatibility
    subscribe,
    unsubscribe,
    subscribeToEvent,
    unsubscribeFromEvent,
    $reset,
  }
})
