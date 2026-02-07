import { ref, computed } from "vue"
import { defineStore } from "pinia"
import { getSessionToken } from "@/api/client"
import { useObjectPoolStore } from "./objectPool"
import type { PoolObject, ObjectType } from "@/types/pool"

type ConnectionState = "disconnected" | "connecting" | "connected" | "authenticated"

interface BroadcastMessage {
  type: "broadcast"
  channel: string
  action: "update" | "delete"
  data: {
    objects: PoolObject[]
  }
}

interface ServerMessage {
  type: string
  channel?: string
  action?: string
  data?: unknown
  userId?: string
  message?: string
}

export const useWebSocketStore = defineStore("websocket", () => {
  const state = ref<ConnectionState>("disconnected")
  const subscribedChannels = ref<Set<string>>(new Set())
  const pendingSubscriptions = ref<Set<string>>(new Set())

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
        handleAuthenticated()
        break
      case "subscribed":
        handleSubscribed(message.channel!)
        break
      case "unsubscribed":
        handleUnsubscribed(message.channel!)
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

  function handleAuthenticated(): void {
    state.value = "authenticated"

    // Start ping interval to keep connection alive
    pingInterval = setInterval(() => {
      send({ type: "ping" })
    }, 30000)

    // Resubscribe to any pending channels
    for (const channel of pendingSubscriptions.value) {
      send({ type: "subscribe", channel })
    }
  }

  function handleSubscribed(channel: string): void {
    subscribedChannels.value.add(channel)
    pendingSubscriptions.value.delete(channel)
  }

  function handleUnsubscribed(channel: string): void {
    subscribedChannels.value.delete(channel)
  }

  function handleBroadcast(message: BroadcastMessage): void {
    const pool = useObjectPoolStore()

    if (message.action === "delete") {
      // Extract type and id from channel (e.g., "event:uuid")
      const [objectType, objectId] = message.channel.split(":", 2)
      pool.remove(objectType as ObjectType, objectId)
    } else if (message.action === "update" && message.data?.objects) {
      pool.importObjects(message.data.objects)
    }
  }

  function send(data: object): void {
    if (socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(data))
    }
  }

  function subscribe(channel: string): void {
    if (subscribedChannels.value.has(channel)) return

    pendingSubscriptions.value.add(channel)

    if (state.value === "authenticated") {
      send({ type: "subscribe", channel })
    }
  }

  function unsubscribe(channel: string): void {
    pendingSubscriptions.value.delete(channel)

    if (subscribedChannels.value.has(channel) && state.value === "authenticated") {
      send({ type: "unsubscribe", channel })
    }

    subscribedChannels.value.delete(channel)
  }

  function subscribeToEvent(eventId: string): void {
    subscribe(`event:${eventId}`)
  }

  function unsubscribeFromEvent(eventId: string): void {
    unsubscribe(`event:${eventId}`)
  }

  function cleanup(): void {
    if (pingInterval) {
      clearInterval(pingInterval)
      pingInterval = null
    }

    // Move active subscriptions to pending for reconnect
    for (const channel of subscribedChannels.value) {
      pendingSubscriptions.value.add(channel)
    }
    subscribedChannels.value.clear()

    socket = null
    state.value = "disconnected"
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

    subscribedChannels.value.clear()
    pendingSubscriptions.value.clear()
    state.value = "disconnected"
    reconnectAttempts = 0
  }

  function $reset(): void {
    disconnect()
  }

  return {
    state,
    subscribedChannels,
    isConnected,
    connect,
    disconnect,
    subscribe,
    unsubscribe,
    subscribeToEvent,
    unsubscribeFromEvent,
    $reset,
  }
})
