import {
  useObjectPoolStore,
  onPoolChange,
  offPoolChange,
} from '@/stores/objectPool'
import { useWebSocketStore } from '@/stores/websocket'
import { WORKSPACE_ID_STORAGE_KEY } from '@/stores/workspace'
import * as poolDb from '@/api/poolDb'
import { CACHE_VERSION } from '@/api/poolDb'
import { Scope } from '@/api/scope'
import { getStaleness } from '@/composables/useStaleness'
import type { PoolChange } from '@/stores/objectPool'
import type { PoolObject, ObjectType } from '@/types/pool'
import { OBJECT_TYPES } from '@/types/pool'

// Object types to load first — these are needed to render the app shell.
// Members and workspace context are required by the nav/header; events are
// the primary content type visible on the home screen.
const PRIORITY_TYPES: ObjectType[] = ['member', 'workspace', 'event']

// Remaining types, in a sensible dependency order so parent objects always
// arrive in the pool before their children.
const DEFERRED_TYPES: ObjectType[] = OBJECT_TYPES.filter(
  (t) => !PRIORITY_TYPES.includes(t)
)

interface PendingSave {
  scope: Scope
  object: PoolObject
}

interface PendingRemove {
  scope: Scope
  objectType: string
  id: string
}

let debounceTimer: ReturnType<typeof setTimeout> | null = null
let idleCallbackHandle: number | null = null
let pendingDebounceTimer: ReturnType<typeof setTimeout> | null = null
let pendingSaves: PendingSave[] = []
let pendingRemoves: PendingRemove[] = []
let changeHandler: ((change: PoolChange) => void) | null = null
let pageHideHandler: (() => void) | null = null

async function flushWrites(): Promise<void> {
  if (idleCallbackHandle !== null) {
    if (typeof cancelIdleCallback === 'function') {
      cancelIdleCallback(idleCallbackHandle)
    } else {
      clearTimeout(idleCallbackHandle)
    }
    idleCallbackHandle = null
  }
  const saves = pendingSaves
  const removes = pendingRemoves
  pendingSaves = []
  pendingRemoves = []
  debounceTimer = null

  try {
    const writes: Promise<unknown>[] = []

    const savesByScope = new Map<Scope, PoolObject[]>()
    for (const s of saves) {
      const bucket = savesByScope.get(s.scope) ?? []
      bucket.push(s.object)
      savesByScope.set(s.scope, bucket)
    }
    for (const [scope, objs] of savesByScope) {
      writes.push(poolDb.saveObjects(scope, objs))
    }

    const removesByScope = new Map<
      Scope,
      { objectType: string; id: string }[]
    >()
    for (const r of removes) {
      const bucket = removesByScope.get(r.scope) ?? []
      bucket.push({ objectType: r.objectType, id: r.id })
      removesByScope.set(r.scope, bucket)
    }
    for (const [scope, entries] of removesByScope) {
      writes.push(poolDb.removeObjects(scope, entries))
    }

    if (writes.length > 0) await Promise.all(writes)
  } catch (e) {
    console.warn('Failed to persist pool objects to IndexedDB', e)
  }
}

function schedulePendingFlush(): void {
  if (pendingDebounceTimer) return
  pendingDebounceTimer = setTimeout(async () => {
    pendingDebounceTimer = null
    try {
      const pool = useObjectPoolStore()
      await poolDb.savePendingUpdates(pool.pendingUpdates)
    } catch (e) {
      console.warn('Failed to persist pending updates to IndexedDB', e)
    }
  }, 500)
}

function scheduleFlush(): void {
  if (debounceTimer) return
  debounceTimer = setTimeout(() => {
    debounceTimer = null
    // Defer the write to an idle period so IndexedDB I/O doesn't compete with
    // active user interactions. Falls back to an immediate async call for
    // environments without requestIdleCallback (Safari < 16, test envs, etc.).
    if (typeof requestIdleCallback === 'function') {
      idleCallbackHandle = requestIdleCallback(flushWrites, { timeout: 2000 })
    } else {
      idleCallbackHandle = setTimeout(flushWrites, 0) as unknown as number
    }
  }, 500)
}

function persistSyncedAtForScope(scope: Scope): void {
  const wsId = Scope.workspaceId(scope)
  if (!wsId) return
  const wsStore = useWebSocketStore()
  const syncedAt = wsStore.getSyncedAt(wsId)
  if (!syncedAt) return
  poolDb.saveSyncedAt(scope, syncedAt).catch((e) => {
    console.warn('Failed to persist syncedAt to IndexedDB', e)
  })
}

async function loadFromCache(): Promise<void> {
  try {
    // Phase 1: Read lightweight metadata only. This is fast on all devices
    // and lets us validate the cache identity before reading any objects.
    const { cacheVersion, syncedAt, fullSyncedAt } = await poolDb.loadMeta()
    if (cacheVersion !== CACHE_VERSION) {
      await poolDb.clearAll()
      return
    }

    const pool = useObjectPoolStore()
    const wsStore = useWebSocketStore()

    // Restore pending overlays before anything can abort the load: they
    // represent commands still in the queue — the replay's rollback needs
    // their ids registered, and the user's offline changes must be visible
    // — regardless of how the object cache races the first sync.
    const pendingUpdates = await poolDb.loadPendingUpdatesFromDb()
    if (pendingUpdates.size > 0) {
      pool.restorePendingUpdates(pendingUpdates)
    }

    // Read from localStorage directly — the workspace store won't be
    // initialized yet since that happens in the WS handleAuthenticated
    // callback
    const expectedWorkspaceId = localStorage.getItem(WORKSPACE_ID_STORAGE_KEY)
    if (!expectedWorkspaceId) return
    if (wsStore.hasSynced) return // Server already sent authoritative data

    const workspaceScopeKey = Scope.workspace(expectedWorkspaceId)
    const workspaceSyncedAt = syncedAt.get(workspaceScopeKey) ?? null
    const workspaceFullSyncedAt = fullSyncedAt.get(workspaceScopeKey) ?? null

    // Check cache age and apply staleness policy. The staleness tier itself
    // is now derived reactively by AuthenticatedLayout from a ticking `now`
    // + the persisted syncedAt — no need to push a static value into the
    // store. We only need the one-shot 'expired' check here to decide
    // whether to clear the workspace scope at load time.
    if (workspaceSyncedAt && getStaleness(workspaceSyncedAt) === 'expired') {
      // Cache is older than 7 days — too stale to trust. Wipe just the
      // active workspace scope; personal data and other workspaces survive.
      await poolDb.clearScope(workspaceScopeKey)
      return
    }

    const scopesToLoad = [Scope.personal(), workspaceScopeKey]

    // Phase 2: Load priority types first (member, workspace, event) so the
    // app shell can render immediately with the most important data.
    // Yield between types so the browser can paint frames.
    let anyLoaded = false
    for (const type of PRIORITY_TYPES) {
      if (wsStore.hasSynced) return // Server beat us — stop loading stale cache
      await new Promise<void>((resolve) => setTimeout(resolve, 0))
      for (const scope of scopesToLoad) {
        const objects = await poolDb.loadObjectsByType(scope, type)
        if (objects.length > 0) {
          pool.importObjects(objects, { scope })
          anyLoaded = true
        }
      }
    }

    // Phase 3: Load remaining types progressively, yielding to the event loop
    // between each type so the browser can paint frames as data arrives.
    for (const type of DEFERRED_TYPES) {
      if (wsStore.hasSynced) break // Server beat us — stop loading stale cache
      await new Promise<void>((resolve) => setTimeout(resolve, 0))
      for (const scope of scopesToLoad) {
        const objects = await poolDb.loadObjectsByType(scope, type)
        if (objects.length > 0) {
          pool.importObjects(objects, { scope })
          anyLoaded = true
        }
      }
    }

    if (!anyLoaded) return

    wsStore.hasCachedData = true

    // Restore the cursors so the next sync can be partial. Only after a
    // successful hydration: a partial sync is only sound against the cached
    // baseline these cursors were saved with.
    if (workspaceSyncedAt) {
      wsStore.restoreSyncTimestamp(expectedWorkspaceId, workspaceSyncedAt)
    }
    if (workspaceFullSyncedAt) {
      wsStore.restoreFullSyncTimestamp(
        expectedWorkspaceId,
        workspaceFullSyncedAt
      )
    }
  } catch {
    // IndexedDB might be unavailable — proceed without cache
  }
}

function persistReplaceScope(scope: Scope, objects: PoolObject[]): void {
  // Drop any pending debounced writes for this scope — the replace is
  // authoritative and would race with stale buffered saves/removes.
  pendingSaves = pendingSaves.filter((s) => s.scope !== scope)
  pendingRemoves = pendingRemoves.filter((r) => r.scope !== scope)

  const wsId = Scope.workspaceId(scope)
  const wsStore = wsId ? useWebSocketStore() : null
  const syncedAt = wsId ? (wsStore!.getSyncedAt(wsId) ?? undefined) : undefined
  // A replace comes from a full sync, whose timestamp the websocket store
  // recorded before applying — persist it so the reconciliation cadence
  // survives restarts.
  const fullSyncedAt = wsId
    ? (wsStore!.getFullSyncedAt(wsId) ?? undefined)
    : undefined

  void poolDb
    .replaceScope(scope, objects, syncedAt, fullSyncedAt)
    .catch((e) => console.warn('Failed to replace scope in IndexedDB', e))
}

function startPersisting(): void {
  if (changeHandler) return

  changeHandler = (change: PoolChange) => {
    if (change.type === 'replaceScope') {
      persistReplaceScope(change.scope, change.objects)
      return
    }

    if (change.type === 'clearScope') {
      // Don't touch the IDB cache here — clearScope is used to free the
      // in-memory pool on a workspace switch, but the cache must survive
      // so a switch-back can rehydrate the previous workspace's data
      // without round-tripping through the server for everything that
      // hasn't changed. Cache clearing for genuine workspace removal goes
      // through replaceScope or an explicit clearAll instead.
      return
    }

    if (change.type === 'import') {
      for (const object of change.objects) {
        pendingSaves.push({ scope: change.scope, object })
      }
      scheduleFlush()
      schedulePendingFlush()
      persistSyncedAtForScope(change.scope)
    } else if (change.type === 'set') {
      pendingSaves.push({ scope: change.scope, object: change.object })
      scheduleFlush()
      schedulePendingFlush()
    } else if (change.type === 'remove') {
      for (const scope of change.scopes) {
        pendingRemoves.push({
          scope,
          objectType: change.objectType,
          id: change.id,
        })
      }
      scheduleFlush()
      schedulePendingFlush()
    }
  }

  onPoolChange(changeHandler)

  // Flush any debounced writes when the page becomes hidden so we don't
  // lose them if the tab is backgrounded, frozen for bfcache, or closed.
  pageHideHandler = () => {
    if (document.visibilityState !== 'hidden') return
    if (debounceTimer === null && idleCallbackHandle === null) return
    if (debounceTimer !== null) {
      clearTimeout(debounceTimer)
      debounceTimer = null
    }
    void flushWrites()
  }
  document.addEventListener('visibilitychange', pageHideHandler)
  window.addEventListener('pagehide', pageHideHandler)
}

function stopPersisting(): void {
  if (changeHandler) {
    offPoolChange(changeHandler)
    changeHandler = null
  }
  if (pageHideHandler) {
    document.removeEventListener('visibilitychange', pageHideHandler)
    window.removeEventListener('pagehide', pageHideHandler)
    pageHideHandler = null
  }
  if (debounceTimer) {
    clearTimeout(debounceTimer)
    debounceTimer = null
  }
  if (idleCallbackHandle !== null) {
    if (typeof cancelIdleCallback === 'function') {
      cancelIdleCallback(idleCallbackHandle)
    } else {
      clearTimeout(idleCallbackHandle)
    }
    idleCallbackHandle = null
  }
  if (pendingDebounceTimer) {
    clearTimeout(pendingDebounceTimer)
    pendingDebounceTimer = null
  }
  pendingSaves = []
  pendingRemoves = []
}

/**
 * Singleton service that mirrors pool changes to IndexedDB. Called once
 * from App.vue on startup (loadFromCache + startPersisting) and once from
 * teardownSession on logout/session-expiry (stopPersisting).
 */
export const poolPersistence = {
  loadFromCache,
  startPersisting,
  stopPersisting,
}
