import {
  useObjectPoolStore,
  onPoolChange,
  offPoolChange,
} from '@/stores/objectPool'
import { useWebSocketStore } from '@/stores/websocket'
import { useWorkspaceStore } from '@/stores/workspace'
import * as poolDb from '@/api/poolDb'
import { CACHE_VERSION } from '@/api/poolDb'
import { getStaleness } from '@/composables/useStaleness'
import type { PoolChange } from '@/stores/objectPool'
import type { PoolObject } from '@/types/pool'

let debounceTimer: ReturnType<typeof setTimeout> | null = null
let pendingDebounceTimer: ReturnType<typeof setTimeout> | null = null
let pendingSaves: PoolObject[] = []
let pendingRemoves: { objectType: string; id: string }[] = []
let changeHandler: ((change: PoolChange) => void) | null = null

async function flushWrites(): Promise<void> {
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
  debounceTimer = setTimeout(flushWrites, 500)
}

export function usePoolPersistence() {
  async function loadFromCache(): Promise<void> {
    // Read from localStorage directly — the workspace store won't be initialized
    // yet since that happens in the WS handleAuthenticated callback
    const expectedWorkspaceId = localStorage.getItem('current_workspace_id')
    if (!expectedWorkspaceId) return

    try {
      const { workspaceId, syncedAt, cacheVersion, objects, pendingUpdates } =
        await poolDb.loadAll()
      if (
        workspaceId !== expectedWorkspaceId ||
        cacheVersion !== CACHE_VERSION
      ) {
        await poolDb.clearAll()
        return
      }
      if (objects.length === 0 && pendingUpdates.size === 0) return

      const pool = useObjectPoolStore()
      const wsStore = useWebSocketStore()
      if (wsStore.hasSynced) return // Server already sent authoritative data

      // Check cache age and apply staleness policy
      if (syncedAt) {
        const staleLevel = getStaleness(syncedAt)

        if (staleLevel === 'expired') {
          // Cache is older than 7 days — too stale to trust. Clear it and force
          // a full sync without showing any cached data.
          await poolDb.clearAll()
          return
        }

        // Expose the staleness level so the UI can show appropriate indicators
        wsStore.setCacheStaleLevel(staleLevel)
      }

      if (objects.length > 0) {
        pool.importObjects(objects)
      }
      if (pendingUpdates.size > 0) {
        pool.restorePendingUpdates(pendingUpdates)
      }

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
  }

  function stopPersisting(): void {
    if (changeHandler) {
      offPoolChange(changeHandler)
      changeHandler = null
    }
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
  }

  return { loadFromCache, startPersisting, stopPersisting }
}
