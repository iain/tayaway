import {
  useObjectPoolStore,
  onPoolChange,
  offPoolChange,
} from '@/stores/objectPool'
import { useWebSocketStore } from '@/stores/websocket'
import { useWorkspaceStore, WORKSPACE_ID_STORAGE_KEY } from '@/stores/workspace'
import * as poolDb from '@/api/poolDb'
import { CACHE_VERSION } from '@/api/poolDb'
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

let debounceTimer: ReturnType<typeof setTimeout> | null = null
let idleCallbackHandle: number | null = null
let pendingDebounceTimer: ReturnType<typeof setTimeout> | null = null
let pendingSaves: PoolObject[] = []
let pendingRemoves: { objectType: string; id: string }[] = []
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
    if (saves.length > 0) await poolDb.saveObjects(saves)
    if (removes.length > 0) await poolDb.removeObjects(removes)
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

export function usePoolPersistence() {
  async function loadFromCache(): Promise<void> {
    // Read from localStorage directly — the workspace store won't be initialized
    // yet since that happens in the WS handleAuthenticated callback
    const expectedWorkspaceId = localStorage.getItem(WORKSPACE_ID_STORAGE_KEY)
    if (!expectedWorkspaceId) return

    try {
      // Phase 1: Read lightweight metadata only. This is fast on all devices
      // and lets us validate the cache identity before reading any objects.
      const { workspaceId, syncedAt, cacheVersion } = await poolDb.loadMeta()
      if (
        workspaceId !== expectedWorkspaceId ||
        cacheVersion !== CACHE_VERSION
      ) {
        await poolDb.clearAll()
        return
      }

      const pool = useObjectPoolStore()
      const wsStore = useWebSocketStore()
      if (wsStore.hasSynced) return // Server already sent authoritative data

      // Check cache age and apply staleness policy. The staleness tier itself
      // is now derived reactively by AuthenticatedLayout from a ticking `now`
      // + the persisted syncedAt — no need to push a static value into the
      // store. We only need the one-shot 'expired' check here to decide
      // whether to clear the cache at load time.
      if (syncedAt && getStaleness(syncedAt) === 'expired') {
        // Cache is older than 7 days — too stale to trust. Clear it and force
        // a full sync without showing any cached data.
        await poolDb.clearAll()
        return
      }

      // Phase 2: Load priority types first (member, workspace, event) so the
      // app shell can render immediately with the most important data.
      // Yield between types so the browser can paint frames.
      let anyLoaded = false
      for (const type of PRIORITY_TYPES) {
        if (wsStore.hasSynced) return // Server beat us — stop loading stale cache
        await new Promise<void>((resolve) => setTimeout(resolve, 0))
        const objects = await poolDb.loadObjectsByType(type)
        if (objects.length > 0) {
          pool.importObjects(objects)
          anyLoaded = true
        }
      }

      // Phase 3: Load remaining types progressively, yielding to the event loop
      // between each type so the browser can paint frames as data arrives.
      for (const type of DEFERRED_TYPES) {
        if (wsStore.hasSynced) break // Server beat us — stop loading stale cache
        await new Promise<void>((resolve) => setTimeout(resolve, 0))
        const objects = await poolDb.loadObjectsByType(type)
        if (objects.length > 0) {
          pool.importObjects(objects)
          anyLoaded = true
        }
      }

      // Phase 4: Restore pending updates regardless of whether cached objects
      // were found — offline changes must survive app restarts even if the
      // object cache was empty.
      if (!wsStore.hasSynced) {
        const pendingUpdates = await poolDb.loadPendingUpdatesFromDb()
        if (pendingUpdates.size > 0) {
          pool.restorePendingUpdates(pendingUpdates)
        }
      }

      if (!anyLoaded) return

      wsStore.hasCachedData = true

      // Restore syncedAt so the next sync can be partial
      if (syncedAt && expectedWorkspaceId) {
        wsStore.restoreSyncTimestamp(expectedWorkspaceId, syncedAt)
      }
    } catch {
      // IndexedDB might be unavailable — proceed without cache
    }
  }

  function startPersisting(): void {
    if (changeHandler) return

    changeHandler = (change: PoolChange) => {
      if (change.type === 'replace') {
        // Full sync from server — replace entire cache
        const workspaceStore = useWorkspaceStore()
        const workspaceId = workspaceStore.currentWorkspaceId
        if (workspaceId) {
          // Cancel any pending debounced writes
          if (debounceTimer) {
            clearTimeout(debounceTimer)
            debounceTimer = null
          }
          if (pendingDebounceTimer) {
            clearTimeout(pendingDebounceTimer)
            pendingDebounceTimer = null
          }
          pendingSaves = []
          pendingRemoves = []
          const wsStore = useWebSocketStore()
          const syncedAt = wsStore.getSyncedAt(workspaceId)
          poolDb
            .replaceAll(workspaceId, change.objects, syncedAt)
            .catch((e) => {
              console.warn('Failed to replace pool cache in IndexedDB', e)
            })
        }
        return
      }

      if (change.type === 'import') {
        pendingSaves.push(...change.objects)
        scheduleFlush()
        schedulePendingFlush()
        // Persist updated syncedAt after partial sync
        const workspaceStore = useWorkspaceStore()
        const wId = workspaceStore.currentWorkspaceId
        if (wId) {
          const wsStore = useWebSocketStore()
          const syncedAt = wsStore.getSyncedAt(wId)
          if (syncedAt) {
            poolDb.saveSyncedAt(syncedAt).catch((e) => {
              console.warn('Failed to persist syncedAt to IndexedDB', e)
            })
          }
        }
      } else if (change.type === 'set') {
        pendingSaves.push(change.object)
        scheduleFlush()
        schedulePendingFlush()
      } else if (change.type === 'remove') {
        pendingRemoves.push({
          objectType: change.objectType,
          id: change.id,
        })
        scheduleFlush()
        schedulePendingFlush()
      }
    }

    onPoolChange(changeHandler)

    // Flush any debounced writes when the page becomes hidden so we don't
    // lose them if the tab is backgrounded, frozen for bfcache, or closed.
    // We listen on BOTH visibilitychange and pagehide:
    //   - visibilitychange fires when the tab loses visibility (OS switch,
    //     new tab, minimise) but the page may still be alive.
    //   - pagehide fires on actual unload/bfcache, including iOS PWA force-
    //     close from the app switcher, which does NOT trigger a prior
    //     visibilitychange. Without this, force-closing the PWA loses any
    //     pool changes that were still sitting in the debounced buffer.
    // The handler is fire-and-forget — we can't reliably await async work
    // from these events, but the browser's unload grace period is typically
    // enough for small IndexedDB writes to commit.
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

  return { loadFromCache, startPersisting, stopPersisting }
}
