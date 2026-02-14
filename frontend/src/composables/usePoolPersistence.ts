import {
  useObjectPoolStore,
  onPoolChange,
  offPoolChange,
} from '@/stores/objectPool'
import { useWebSocketStore } from '@/stores/websocket'
import { useWorkspaceStore } from '@/stores/workspace'
import * as poolDb from '@/api/poolDb'
import type { PoolChange } from '@/stores/objectPool'
import type { PoolObject } from '@/types/pool'

let debounceTimer: ReturnType<typeof setTimeout> | null = null
let pendingSaves: PoolObject[] = []
let pendingRemoves: { objectType: string; id: string }[] = []
let changeHandler: ((change: PoolChange) => void) | null = null

function flushWrites(): void {
  const saves = pendingSaves
  const removes = pendingRemoves
  pendingSaves = []
  pendingRemoves = []
  debounceTimer = null

  if (saves.length > 0) poolDb.saveObjects(saves)
  if (removes.length > 0) poolDb.removeObjects(removes)
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
      const { workspaceId, objects } = await poolDb.loadAll()
      if (workspaceId !== expectedWorkspaceId) {
        await poolDb.clearAll()
        return
      }
      if (objects.length === 0) return

      const pool = useObjectPoolStore()
      pool.importObjects(objects)

      const wsStore = useWebSocketStore()
      wsStore.hasCachedData = true
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
          pendingSaves = []
          pendingRemoves = []
          poolDb.replaceAll(workspaceId, change.objects)
        }
        return
      }

      if (change.type === 'import') {
        pendingSaves.push(...change.objects)
        scheduleFlush()
      } else if (change.type === 'set') {
        pendingSaves.push(change.object)
        scheduleFlush()
      } else if (change.type === 'remove') {
        pendingRemoves.push({
          objectType: change.objectType,
          id: change.id,
        })
        scheduleFlush()
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
    pendingSaves = []
    pendingRemoves = []
  }

  return { loadFromCache, startPersisting, stopPersisting }
}
