import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { useObjectPoolStore } from './objectPool'
import type { PoolWorkspace, PoolObject } from '@/types/pool'
import { OBJECT_TYPES } from '@/types/pool'
import {
  loadObjectsByType,
  setCurrentWorkspaceId,
  workspaceScope,
} from '@/api/poolDb'

// Exported so other modules (poolPersistence cold-start, websocket
// reconnect URL) can read the same key without hardcoding the string.
export const WORKSPACE_ID_STORAGE_KEY = 'current_workspace_id'
const STORAGE_KEY = WORKSPACE_ID_STORAGE_KEY

export const useWorkspaceStore = defineStore('workspace', () => {
  const currentWorkspaceId = ref<string | null>(null)

  const pool = useObjectPoolStore()

  const currentWorkspace = computed<PoolWorkspace | undefined>(() => {
    if (!currentWorkspaceId.value) return undefined
    return pool.get('workspace', currentWorkspaceId.value)
  })

  const allWorkspaces = computed<PoolWorkspace[]>(() => {
    return pool.getAll('workspace')
  })

  const otherWorkspaces = computed<PoolWorkspace[]>(() => {
    return allWorkspaces.value.filter((w) => w.id !== currentWorkspaceId.value)
  })

  function initialize(workspaceIds: string[]): void {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored && workspaceIds.includes(stored)) {
      currentWorkspaceId.value = stored
    } else if (workspaceIds.length > 0) {
      currentWorkspaceId.value = workspaceIds[0]!
      localStorage.setItem(STORAGE_KEY, workspaceIds[0]!)
    }
  }

  function switchWorkspace(id: string): void {
    currentWorkspaceId.value = id
    localStorage.setItem(STORAGE_KEY, id)

    // In-memory: drop the previous workspace's data. Personal data (own
    // memberships, workspace rows, notifications) survives via clearExcept.
    pool.clearExcept('workspace')

    // Persist the new active workspace marker so cold-starts pick it up.
    setCurrentWorkspaceId(id).catch(() => {})

    // Hydrate the new workspace's cached data into the pool so the UI
    // can render before the partial sync arrives. Personal data is
    // already in memory from the previous workspace. Each type yields
    // to the event loop between loads so the browser can paint frames.
    void hydrateCachedWorkspace(id)
  }

  async function hydrateCachedWorkspace(id: string): Promise<void> {
    const scope = workspaceScope(id)
    let loadedAny = false
    for (const type of OBJECT_TYPES) {
      // Stop if the user has switched again — don't hydrate stale data
      // into a different workspace's active view.
      if (currentWorkspaceId.value !== id) return
      try {
        const cached: PoolObject[] = await loadObjectsByType(scope, type)
        if (cached.length > 0 && currentWorkspaceId.value === id) {
          pool.importObjects(cached)
          loadedAny = true
        }
      } catch {
        // IndexedDB unavailable — proceed without cached data.
      }
    }
    // Suppress the full-page loader during the gap between the WS switch
    // request and the partial sync response — cached data is on screen.
    if (loadedAny && currentWorkspaceId.value === id) {
      const { useWebSocketStore } = await import('./websocket')
      useWebSocketStore().hasCachedData = true
    }
  }

  function $reset(): void {
    currentWorkspaceId.value = null
    localStorage.removeItem(STORAGE_KEY)
  }

  return {
    currentWorkspaceId,
    currentWorkspace,
    allWorkspaces,
    otherWorkspaces,
    initialize,
    switchWorkspace,
    $reset,
  }
})
