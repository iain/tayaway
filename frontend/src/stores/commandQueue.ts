import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { rawApi, type ApiResponse } from '@/api/client'
import { processPoolResponse } from '@/api/processPoolResponse'
import { Scope } from '@/api/scope'
import {
  addCommand,
  removeCommand,
  getPendingCommands,
  count as dbCount,
  clearAll,
} from '@/api/commandDb'
import { coalesceCommands } from '@/api/coalesceCommands'
import { useWebSocketStore } from './websocket'
import { useWorkspaceStore } from './workspace'

export class CommandQueuedError extends Error {
  constructor() {
    super('Command queued for later execution')
    this.name = 'CommandQueuedError'
  }
}

// Failures where the command should stay queued for a later retry. Replays
// carry an Idempotency-Key, so retrying is safe even when the original
// request reached the server.
function isRetryableError(e: unknown): boolean {
  // fetch() rejects with TypeError only for network failures per the fetch
  // spec, so instanceof alone is a complete and robust check. The previous
  // substring match on browser-specific wordings ("Failed to fetch", "Load
  // failed", "NetworkError…") would silently regress on any wording change.
  if (e instanceof TypeError) return true
  // Timeouts surface as DOMExceptions ('TimeoutError' from the client's
  // AbortSignal.timeout, 'AbortError' from a plain abort), not TypeErrors.
  // Whether the request reached the server is unknown — don't drop it.
  if (
    e instanceof DOMException &&
    (e.name === 'TimeoutError' || e.name === 'AbortError')
  ) {
    return true
  }
  // Gateway errors are what a deploy window looks like from the client —
  // the backend is restarting behind the proxy and will be back shortly.
  return (
    typeof e === 'object' &&
    e !== null &&
    'status' in e &&
    [502, 503, 504].includes((e as { status: number }).status)
  )
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
  const retryRequested = ref(false)

  // A working, authenticated WebSocket is the only reliable "we are online"
  // signal. navigator.onLine returns true on captive portals, dead WiFi, and
  // any network that dropped without the OS noticing, so we can't trust it.
  // Reconnecting the WS already triggers processQueue() from the websocket
  // store's handleAuthenticated callback, so we don't need separate online
  // listeners here.
  const isOnline = computed(() => useWebSocketStore().state === 'authenticated')

  async function initialize(): Promise<void> {
    pendingCount.value = await dbCount()
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
    const workspaceId = useWorkspaceStore().currentWorkspaceId ?? null
    const commandId = await addCommand({ method, path, body, workspaceId })
    pendingCount.value++

    try {
      const response = await executeRequest<T>(
        method,
        path,
        body,
        idempotencyKeyFor([commandId]),
        workspaceId
      )
      await removeCommand(commandId)
      pendingCount.value--
      return response
    } catch (e) {
      if (isRetryableError(e)) {
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
    const { handleSessionExpired } = await import('@/api/sessionExpired')
    await handleSessionExpired()
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
            await new Promise<void>((r) => setTimeout(r, 0))
          }
        }

        // Execute coalesced commands, removing original IDs on success
        for (const command of coalesced) {
          // Yield to the event loop between commands so the browser can paint
          // frames and handle user input during a long offline replay.
          await new Promise<void>((r) => setTimeout(r, 0))
          try {
            await executeRequest(
              command.method,
              command.path,
              command.body,
              idempotencyKeyFor(command.originalIds),
              command.workspaceId ?? null
            )
            for (const id of command.originalIds) {
              await removeCommand(id)
              await new Promise<void>((r) => setTimeout(r, 0))
            }
            pendingCount.value -= command.originalIds.length
          } catch (e) {
            if (isAuthError(e)) {
              // Session expired — keep commands, redirect to login
              await handleAuthError()
              break
            }
            if (isRetryableError(e)) {
              // Still offline (or the backend is mid-deploy) — stop
              // processing; the queue replays on the next trigger.
              break
            }
            // Server error — remove and notify, continue with next
            try {
              for (const id of command.originalIds) {
                await removeCommand(id)
                await new Promise<void>((r) => setTimeout(r, 0))
              }
              pendingCount.value -= command.originalIds.length
            } catch {
              // removeCommand failed — count will be resynced in finally block
            }
            const { useNotificationsStore } = await import('./notifications')
            const notifications = useNotificationsStore()
            notifications.showError(
              "An offline change couldn't be saved. Please try again."
            )
          }
        }
      } while (retryRequested.value)
    } catch {
      // Unexpected error escaped the inner loop — resync to avoid drift
    } finally {
      isProcessing.value = false
      await resyncPendingCount()
    }
  }

  async function reset(): Promise<void> {
    await clearAll()
    pendingCount.value = 0
    isProcessing.value = false
  }

  function $reset(): void {
    // Synchronous reset for Pinia — async cleanup handled by reset()
    pendingCount.value = 0
    isProcessing.value = false
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

// Exported for tests. The key for a coalesced command is the sorted set of
// its source command ids joined with a comma. Each source id is a UUID
// generated at enqueue time and persisted in IndexedDB, so the derived key
// is stable across retries of the same logical operation. A retry that
// follows a *different* coalescing pass (new commands queued during the
// offline window) produces a different key and is treated as a fresh
// request — acceptable because the routes the queue retries are themselves
// idempotent at the row level.
export function idempotencyKeyFor(originalIds: string[]): string {
  return [...originalIds].sort().join(',')
}

async function executeRequest<T>(
  method: 'POST' | 'PUT' | 'PATCH' | 'DELETE',
  path: string,
  body?: unknown,
  idempotencyKey?: string,
  workspaceId?: string | null
): Promise<ApiResponse<T>> {
  const opts = idempotencyKey ? { idempotencyKey } : undefined
  const response =
    method === 'POST'
      ? await rawApi.post<T>(path, body, opts)
      : method === 'PUT'
        ? await rawApi.put<T>(path, body, opts)
        : method === 'PATCH'
          ? await rawApi.patch<T>(path, body, opts)
          : await rawApi.delete<T>(path, opts)
  // Successful mutations hydrate the pool explicitly here instead of as a
  // hidden side effect inside the HTTP client, so rawApi stays pure and
  // the coupling is visible at the only layer that actually needs it. The
  // workspaceId snapshot from enqueue time is threaded through so a
  // workspace switch between enqueue and replay doesn't misroute the
  // response into the new workspace's scope.
  const scope = workspaceId ? Scope.workspace(workspaceId) : undefined
  processPoolResponse(response.data, scope)
  return response
}
