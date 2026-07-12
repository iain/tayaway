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
  type OptimisticRef,
} from '@/api/commandDb'
import { coalesceCommands } from '@/api/coalesceCommands'
import { useWebSocketStore } from './websocket'
import { useWorkspaceStore } from './workspace'
import { useObjectPoolStore } from './objectPool'

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

// Undo the optimistic state a permanently-failed replay left in the pool.
// Without this the UI keeps showing a change the server rejected: temp
// creates survive every full sync (tempObjectIds preserves them) and
// "newer than server" overlays survive replaceScope and restarts.
function rollbackOptimistic(ref: OptimisticRef): void {
  const pool = useObjectPoolStore()
  if (ref.kind === 'create') {
    pool.cascadeRemove(ref.objectType, ref.objectId)
  } else if (ref.kind === 'update') {
    pool.removePending(ref.pendingId)
  } else {
    pool.restore(ref.removed)
  }
}

function humanObjectType(type: string): string {
  if (type === 'rsvp') {
    return 'RSVP'
  }
  // camelCase → spaced lowercase: taskItem → "task item"
  return type
    .replace(/([A-Z])/g, ' $1')
    .toLowerCase()
    .trim()
}

// Human label for one rolled-back ref.
function labelForRef(ref: OptimisticRef): string | null {
  const type =
    ref.kind === 'destroy' ? ref.removed[0]?.object.objectType : ref.objectType
  return type ? humanObjectType(type) : null
}

// Only claim "undone" for changes that actually had a rollback linkage —
// commands enqueued outside useMutation manage their own optimistic state
// and nothing here reconciles them.
function replayFailureMessage(
  rolledBack: (string | null)[],
  unlinked: number
): string {
  const total = rolledBack.length + unlinked
  if (unlinked === 0) {
    if (total === 1) {
      const label = rolledBack[0]
      return label
        ? `Your offline ${label} change couldn't be saved and was undone.`
        : "An offline change couldn't be saved and was undone."
    }
    return `${total} offline changes couldn't be saved and were undone.`
  }
  if (rolledBack.length === 0) {
    return total === 1
      ? "An offline change couldn't be saved."
      : `${total} offline changes couldn't be saved.`
  }
  return `${total} offline changes couldn't be saved; ${rolledBack.length} ${
    rolledBack.length === 1 ? 'was' : 'were'
  } undone.`
}

// Backoff for replays that fail while the WebSocket stays healthy. Without
// a self-scheduled retry, a command queued by a fetch blip too short to
// drop the socket sits in IndexedDB until the next reconnect or app
// restart — the only other processQueue triggers.
const BASE_RETRY_DELAY_MS = 5_000
const MAX_RETRY_DELAY_MS = 60_000

export const useCommandQueueStore = defineStore('commandQueue', () => {
  const pendingCount = ref(0)
  const isProcessing = ref(false)
  const retryRequested = ref(false)
  // True while a backoff retry is armed — surfaced so the pending-changes
  // pill can show queued work even when the socket looks healthy.
  const retryScheduled = ref(false)

  let retryTimer: ReturnType<typeof setTimeout> | null = null
  let retryDelayMs = BASE_RETRY_DELAY_MS

  // A working, authenticated WebSocket is the only reliable "we are online"
  // signal. navigator.onLine returns true on captive portals, dead WiFi, and
  // any network that dropped without the OS noticing, so we can't trust it.
  // Reconnecting the WS already triggers processQueue() from the websocket
  // store's handleAuthenticated callback, so we don't need separate online
  // listeners here.
  const isOnline = computed(() => useWebSocketStore().state === 'authenticated')

  // Arm a retry for queued commands. Only while the socket is up — when it
  // is down, the reconnect's processQueue trigger covers replay, and a
  // timer would just burn failed fetches.
  function scheduleRetry(): void {
    if (retryTimer !== null) return
    if (!isOnline.value) return
    retryScheduled.value = true
    retryTimer = setTimeout(() => {
      retryTimer = null
      retryScheduled.value = false
      void processQueue()
    }, retryDelayMs)
    retryDelayMs = Math.min(retryDelayMs * 2, MAX_RETRY_DELAY_MS)
  }

  function clearRetry(): void {
    if (retryTimer !== null) {
      clearTimeout(retryTimer)
      retryTimer = null
    }
    retryScheduled.value = false
    retryDelayMs = BASE_RETRY_DELAY_MS
  }

  async function initialize(): Promise<void> {
    const commands = await getPendingCommands()
    pendingCount.value = commands.length

    // Re-mark queued creates as temp: tempObjectIds is in-memory, so after
    // a restart the optimistic objects hydrated from the cache would be
    // dropped by the next (reconciliation) full sync while their create
    // commands are still waiting to replay.
    const pool = useObjectPoolStore()
    for (const command of commands) {
      if (command.optimistic?.kind === 'create') {
        pool.markTemp(command.optimistic.objectId)
      }
    }

    if (pendingCount.value > 0) {
      processQueue()
    }
  }

  async function resyncPendingCount(): Promise<void> {
    pendingCount.value = await dbCount()
  }

  // Rows whose direct request is still in flight. processQueue must skip
  // them: replaying one duplicates the request and double-decrements
  // pendingCount when both paths succeed.
  const inFlightCommandIds = new Set<string>()

  async function enqueue<T>(
    method: 'POST' | 'PUT' | 'PATCH' | 'DELETE',
    path: string,
    body?: unknown,
    optimistic?: OptimisticRef
  ): Promise<ApiResponse<T>> {
    const workspaceId = useWorkspaceStore().currentWorkspaceId ?? null
    // The rollback linkage is written atomically with the row — a linkage
    // registered after the fact leaves a window where a raced replay can
    // permanently fail with nothing to roll back.
    const commandId = await addCommand({
      method,
      path,
      body,
      workspaceId,
      optimistic,
    })
    pendingCount.value++
    inFlightCommandIds.add(commandId)

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
      retryDelayMs = BASE_RETRY_DELAY_MS
      return response
    } catch (e) {
      if (isRetryableError(e)) {
        scheduleRetry()
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
    } finally {
      inFlightCommandIds.delete(commandId)
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

    // Human labels of rolled-back optimistic changes plus a count of failed
    // commands that had no rollback linkage, accumulated across the whole
    // drain so the user gets one honest toast, not one per failure.
    const failedRollbacks: (string | null)[] = []
    let unlinkedFailures = 0
    // After a 401 the session is being torn down — arming a retry would
    // just hammer the API with commands that keep 401ing.
    let authFailed = false
    // Only arm the self-retry when this drain actually hit a retryable
    // failure; rows left behind for other reasons (in-flight direct
    // requests) don't need one.
    let sawRetryableFailure = false

    try {
      do {
        retryRequested.value = false
        const commands = (await getPendingCommands()).filter(
          (c) => !inFlightCommandIds.has(c.id)
        )
        const commandsById = new Map(commands.map((c) => [c.id, c]))
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
            retryDelayMs = BASE_RETRY_DELAY_MS
          } catch (e) {
            if (isAuthError(e)) {
              // Session expired — keep commands, redirect to login
              authFailed = true
              await handleAuthError()
              break
            }
            if (isRetryableError(e)) {
              // Still offline (or the backend is mid-deploy) — stop
              // processing; the queue replays on the next trigger.
              sawRetryableFailure = true
              break
            }
            // Permanent server rejection — undo whatever optimistic state
            // the original commands registered, drop them, and record each
            // rolled-back change (not each coalesced group) for the
            // combined toast below.
            const refs = command.originalIds
              .map((id) => commandsById.get(id)?.optimistic)
              .filter((ref): ref is OptimisticRef => ref !== undefined)
            if (refs.length > 0) {
              for (const ref of refs) {
                rollbackOptimistic(ref)
                failedRollbacks.push(labelForRef(ref))
              }
            } else {
              unlinkedFailures++
            }
            try {
              for (const id of command.originalIds) {
                await removeCommand(id)
                await new Promise<void>((r) => setTimeout(r, 0))
              }
              pendingCount.value -= command.originalIds.length
            } catch {
              // removeCommand failed — count will be resynced in finally block
            }
          }
        }
      } while (retryRequested.value)
    } catch {
      // Unexpected error escaped the inner loop — resync to avoid drift
    } finally {
      // Notify from the finally so an unexpected error later in the drain
      // can't suppress the toast for rollbacks that already happened.
      if (failedRollbacks.length > 0 || unlinkedFailures > 0) {
        try {
          const { useNotificationsStore } = await import('./notifications')
          useNotificationsStore().showError(
            replayFailureMessage(failedRollbacks, unlinkedFailures)
          )
        } catch {
          // Notifying is best-effort — never mask the drain outcome
        }
      }
      isProcessing.value = false
      await resyncPendingCount()
      if (pendingCount.value === 0) {
        // Fully drained — disarm any pending retry and reset the backoff
        clearRetry()
      } else if (!authFailed && sawRetryableFailure) {
        // A retryable failure left commands behind — make sure a retry is
        // armed; a no-op when the socket is down, since the reconnect
        // trigger covers that case.
        scheduleRetry()
      }
    }
  }

  async function reset(): Promise<void> {
    await clearAll()
    pendingCount.value = 0
    isProcessing.value = false
    clearRetry()
  }

  function $reset(): void {
    // Synchronous reset for Pinia — async cleanup handled by reset()
    pendingCount.value = 0
    isProcessing.value = false
    clearRetry()
  }

  return {
    pendingCount,
    isProcessing,
    retryScheduled,
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
  let response: ApiResponse<T>
  try {
    response =
      method === 'POST'
        ? await rawApi.post<T>(path, body, opts)
        : method === 'PUT'
          ? await rawApi.put<T>(path, body, opts)
          : method === 'PATCH'
            ? await rawApi.patch<T>(path, body, opts)
            : await rawApi.delete<T>(path, opts)
  } catch (e) {
    // A 404 on DELETE means the object is already gone server-side —
    // deleted by another device/user, or a local-only zombie that never
    // existed there. That's the outcome the delete wanted, so treat it as
    // success: failing instead would restore/roll back the optimistic
    // removal and resurrect an object the user can never get rid of.
    // There is no response body to hydrate the pool from; the optimistic
    // removal already took care of the local state.
    if (
      method === 'DELETE' &&
      typeof e === 'object' &&
      e !== null &&
      'status' in e &&
      (e as { status: number }).status === 404
    ) {
      return { data: null as T, status: 404 }
    }
    throw e
  }
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
