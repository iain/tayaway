import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { useObjectPoolStore } from './objectPool'
import type { PoolWorkspace } from '@/types/pool'

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
    // Phase 4 will replace this clear with a per-workspace pool that
    // preserves both workspaces in memory.
    pool.clearExcept('workspace')

    // IndexedDB: persist the new active workspace and let the new
    // workspace's sync replace its own scope. Other workspaces' caches
    // are preserved so a switch-back can hydrate from them.
    import('@/api/poolDb')
      .then((poolDb) => poolDb.setCurrentWorkspaceId(id))
      .catch(() => {})
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
