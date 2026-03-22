import { ref } from 'vue'
import { defineStore } from 'pinia'
import { api, type ApiResponse } from '@/api/client'
import {
  addCommand,
  removeCommand,
  getPendingCommands,
  count as dbCount,
  clearAll,
} from '@/api/commandDb'
import { coalesceCommands } from '@/api/coalesceCommands'

export class CommandQueuedError extends Error {
  constructor() {
    super('Command queued for later execution')
    this.name = 'CommandQueuedError'
  }
}

function isNetworkError(e: unknown): boolean {
  if (!(e instanceof TypeError)) return false
  if (!navigator.onLine) return true
  const msg = e.message.toLowerCase()
  return msg.includes('fetch') || msg.includes('network')
}

function isAuthError(e: unknown): boolean {
  return (
    typeof e === 'object' &&
    e !== null &&
    'status' in e &&
    (e as { status: number }).status === 401
  )
}

export const useCommandQueueStore = defineStore('commandQueue', () => {
  const pendingCount = ref(0)
  const isProcessing = ref(false)
  const isOnline = ref(navigator.onLine)
  const retryRequested = ref(false)

  function handleOnline() {
    isOnline.value = true
    processQueue()
  }

  function handleOffline() {
    isOnline.value = false
  }

  async function initialize(): Promise<void> {
    pendingCount.value = await dbCount()
    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)
    if (pendingCount.value > 0) {
      processQueue()
    }
  }

  async function resyncPendingCount(): Promise<void> {
    pendingCount.value = await dbCount()
  }

  async function enqueue<T>(
    method: 'POST' | 'PUT' | 'PATCH' | 'DELETE',
    path: string,
    body?: unknown
  ): Promise<ApiResponse<T>> {
    const commandId = await addCommand({ method, path, body })
    pendingCount.value++

    try {
      const response = await executeRequest<T>(method, path, body)
      await removeCommand(commandId)
      pendingCount.value--
      return response
    } catch (e) {
      if (isNetworkError(e)) {
        throw new CommandQueuedError()
      }
      if (isAuthError(e)) {
        // Session expired — keep command in queue for replay after re-auth
        await handleAuthError()
        throw new CommandQueuedError()
      }
      // Server error — remove from queue and rethrow
      try {
        await removeCommand(commandId)
        pendingCount.value--
      } catch {
        // removeCommand failed — resync count from IndexedDB to avoid drift
        await resyncPendingCount()
      }
      throw e
    }
  }

  async function handleAuthError(): Promise<void> {
    const { useNotificationsStore } = await import('./notifications')
    const notifications = useNotificationsStore()
    notifications.showError('Your session has expired. Please log in again.')
    const { useWebSocketStore } = await import('./websocket')
    const wsStore = useWebSocketStore()
    wsStore.disconnect()
    const { useAuthStore } = await import('./auth')
    const authStore = useAuthStore()
    authStore.$reset()
    const { default: router } = await import('@/router')
    router.push({ name: 'login' })
  }

  async function processQueue(): Promise<void> {
    if (isProcessing.value) {
      retryRequested.value = true
      return
    }
    isProcessing.value = true
    let hadError = false

    try {
      do {
        retryRequested.value = false
        const commands = await getPendingCommands()
        const coalesced = coalesceCommands(commands)

        // Remove cancelled-out commands from IndexedDB immediately
        const survivingIds = new Set(coalesced.flatMap((c) => c.originalIds))
        for (const cmd of commands) {
          if (!survivingIds.has(cmd.id)) {
            await removeCommand(cmd.id)
            pendingCount.value--
          }
        }

        // Execute coalesced commands, removing original IDs on success
        for (const command of coalesced) {
          try {
            await executeRequest(command.method, command.path, command.body)
            for (const id of command.originalIds) {
              await removeCommand(id)
            }
            pendingCount.value -= command.originalIds.length
          } catch (e) {
            if (isAuthError(e)) {
              // Session expired — keep commands, redirect to login
              await handleAuthError()
              break
            }
            if (isNetworkError(e)) {
              // Still offline, stop processing
              break
            }
            // Server error — remove and notify, continue with next
            hadError = true
            try {
              for (const id of command.originalIds) {
                await removeCommand(id)
              }
              pendingCount.value -= command.originalIds.length
            } catch {
              // removeCommand failed — count will be resynced in finally block
            }
            const { useNotificationsStore } = await import('./notifications')
            const notifications = useNotificationsStore()
            notifications.showError(
              `Failed to sync offline change: ${command.method} ${command.path}`
            )
          }
        }
      } while (retryRequested.value)
    } catch {
      // Unexpected error escaped the inner loop — resync to avoid drift
      hadError = true
    } finally {
      isProcessing.value = false
      if (hadError) {
        await resyncPendingCount()
      }
    }
  }

  async function reset(): Promise<void> {
    window.removeEventListener('online', handleOnline)
    window.removeEventListener('offline', handleOffline)
    await clearAll()
    pendingCount.value = 0
    isProcessing.value = false
  }

  function $reset(): void {
    // Synchronous reset for Pinia — async cleanup handled by reset()
    pendingCount.value = 0
    isProcessing.value = false
    isOnline.value = navigator.onLine
  }

  return {
    pendingCount,
    isProcessing,
    isOnline,
    initialize,
    enqueue,
    processQueue,
    reset,
    $reset,
  }
})

function executeRequest<T>(
  method: 'POST' | 'PUT' | 'PATCH' | 'DELETE',
  path: string,
  body?: unknown
): Promise<ApiResponse<T>> {
  switch (method) {
    case 'POST':
      return api.post<T>(path, body)
    case 'PUT':
      return api.put<T>(path, body)
    case 'PATCH':
      return api.patch<T>(path, body)
    case 'DELETE':
      return api.delete<T>(path)
  }
}
