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
      // Server error — remove from queue and rethrow
      await removeCommand(commandId)
      pendingCount.value--
      throw e
    }
  }

  async function processQueue(): Promise<void> {
    if (isProcessing.value) {
      retryRequested.value = true
      return
    }
    isProcessing.value = true

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
            if (isNetworkError(e)) {
              // Still offline, stop processing
              break
            }
            // Server error — remove and notify, continue with next
            for (const id of command.originalIds) {
              await removeCommand(id)
            }
            pendingCount.value -= command.originalIds.length
            const { useNotificationsStore } = await import('./notifications')
            const notifications = useNotificationsStore()
            notifications.showError(
              `Failed to sync offline change: ${command.method} ${command.path}`
            )
          }
        }
      } while (retryRequested.value)
    } finally {
      isProcessing.value = false
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
