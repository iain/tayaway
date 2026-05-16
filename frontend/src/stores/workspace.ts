import { ref, computed, watch } from 'vue'
import { defineStore } from 'pinia'
import { useObjectPoolStore } from './objectPool'
import type { PoolWorkspace, PoolObject } from '@/types/pool'
import { OBJECT_TYPES } from '@/types/pool'
import { loadObjectsByType } from '@/api/poolDb'
import { Scope } from '@/api/scope'

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

  // Single entry point for "user wants to be in workspace X." Updates local
  // state, clears the previous workspace's scope from the pool (objects also
  // in personal scope survive — the workspace selector, own memberships,
  // notifications), kicks off cache hydration so the UI shows something
  // instantly on switch-back, and tells the server to swap our workspace
  // subscription. Callers in components don't need to coordinate these
  // steps themselves.
  async function switchWorkspace(id: string): Promise<void> {
    const previousId = currentWorkspaceId.value
    currentWorkspaceId.value = id
    localStorage.setItem(STORAGE_KEY, id)
    if (previousId && previousId !== id) {
      pool.clearScope(Scope.workspace(previousId))
    }

    const { useWebSocketStore } = await import('./websocket')
    useWebSocketStore().sendSwitchWorkspace(id)

    void hydrateCachedWorkspace(id)
  }

  async function hydrateCachedWorkspace(id: string): Promise<void> {
    const scope = Scope.workspace(id)
    for (const type of OBJECT_TYPES) {
      // Stop if the user has switched again — don't hydrate stale data
      // into a different workspace's active view.
      if (currentWorkspaceId.value !== id) return
      try {
        const cached: PoolObject[] = await loadObjectsByType(scope, type)
        if (cached.length > 0 && currentWorkspaceId.value === id) {
          pool.importObjects(cached, { scope })
          // Yield after a non-empty import so the browser can paint
          // between chunks. Empty buckets are cheap and don't need it.
          await new Promise<void>((resolve) => setTimeout(resolve, 0))
        }
      } catch {
        // IndexedDB unavailable — proceed without cached data.
      }
    }
  }

  // Track whether we've ever seen the authoritative workspace list. Until the
  // first non-empty list arrives, an empty pool is "not loaded yet" rather
  // than "you have no workspaces" — guards the cold-start path before the
  // personal sync hydrates the pool.
  let workspacesEverLoaded = false

  // If the user gets removed from the workspace they're currently looking at,
  // the personal-channel broadcast drops the workspace row from the pool.
  // Redirect to the next remaining workspace so the UI doesn't sit on a stale
  // workspace context. If there are no workspaces left, clear and let the
  // empty state take over.
  //
  // `flush: 'sync'` runs the handler in the same microtask as the pool
  // mutation; the alternative ('pre' / 'post') defers to the next render
  // tick, by which point a route guard or computed reading
  // currentWorkspaceId can have already evaluated against the stale id.
  // `immediate: true` lets the gate fire on registration; the
  // workspacesEverLoaded flag stops the cold start from clearing the
  // active workspace before personal sync delivers the workspace list.
  watch(
    allWorkspaces,
    (all) => {
      if (all.length > 0) workspacesEverLoaded = true
      if (!workspacesEverLoaded) return
      const wsId = currentWorkspaceId.value
      if (!wsId) return
      if (all.length === 0) {
        currentWorkspaceId.value = null
        localStorage.removeItem(STORAGE_KEY)
        return
      }
      if (!all.some((w) => w.id === wsId)) {
        switchWorkspace(all[0]!.id).catch((e) => {
          console.error('Auto-switch after workspace removal failed', e)
        })
      }
    },
    { flush: 'sync', immediate: true }
  )

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
