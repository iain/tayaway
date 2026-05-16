import { ref } from 'vue'
import { useCommandQueueStore, CommandQueuedError } from '@/stores/commandQueue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useWorkspaceStore } from '@/stores/workspace'
import { workspaceScope } from '@/api/poolDb'
import type { ApiResponse } from '@/api/client'
import type { ObjectType, ObjectTypeMap, PoolObject } from '@/types/pool'

// Optimistic creates land in the workspace's scope so the matching server
// confirmation, which arrives on the same channel, merges into the same
// bucket. Most pool objects carry their own workspaceId, so prefer that
// over the global "current workspace" — it's resilient to a rapid switch
// while a mutation is in flight, and to tests that don't mock the
// workspace store.
function scopeForOptimisticObject(obj: PoolObject): string {
  const objectWsId = (obj as { workspaceId?: string | null }).workspaceId
  if (objectWsId) return workspaceScope(objectWsId)
  // In production the workspace store is always initialized by the time a
  // mutation fires (handleAuthenticated does it before any mutation control
  // is even rendered). The 'test' fallback exists for unit tests that
  // exercise pool semantics without an authenticated workspace — pool reads
  // are scope-agnostic, so the synthetic tag has no observable effect.
  const wsId = useWorkspaceStore().currentWorkspaceId ?? 'test'
  return workspaceScope(wsId)
}

export type MutationResult<T> = { queued: false; data: T } | { queued: true }

/**
 * Composable that wraps commandQueue.enqueue() with loading/error state management
 * and pool-aware optimistic update helpers.
 *
 * Returns MutationResult instead of throwing CommandQueuedError, keeping the
 * offline queueing mechanism invisible to callers.
 */
export function useMutation() {
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function mutate<T>(
    errorMessage: string,
    fn: (
      commandQueue: ReturnType<typeof useCommandQueueStore>
    ) => Promise<ApiResponse<T>>
  ): Promise<MutationResult<T>> {
    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      const response = await fn(commandQueue)
      return { queued: false, data: response.data }
    } catch (e) {
      if (e instanceof CommandQueuedError) {
        return { queued: true }
      }
      error.value = errorMessage
      throw e
    } finally {
      loading.value = false
    }
  }

  /**
   * Optimistic create: adds a temp object to the pool, then fires the API call.
   * On success: server response auto-imports via client interceptor, replacing temp.
   * On queued: keeps optimistic state.
   * On error: removes the temp object and rethrows.
   */
  async function create<T>(
    errorMessage: string,
    tempObject: ObjectTypeMap[ObjectType],
    fn: (
      commandQueue: ReturnType<typeof useCommandQueueStore>
    ) => Promise<ApiResponse<T>>
  ): Promise<MutationResult<T>> {
    const pool = useObjectPoolStore()
    pool.set(scopeForOptimisticObject(tempObject), tempObject, { isTemp: true })

    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      const response = await fn(commandQueue)
      return { queued: false, data: response.data }
    } catch (e) {
      if (e instanceof CommandQueuedError) {
        return { queued: true }
      }
      pool.cascadeRemove(tempObject.objectType, tempObject.id)
      error.value = errorMessage
      throw e
    } finally {
      loading.value = false
    }
  }

  /**
   * Optimistic update: adds pending changes to the pool, then fires the API call.
   * On success: server response auto-imports, clearing pending.
   * On queued: keeps pending state.
   * On error: removes pending changes and rethrows.
   */
  async function update<T>(
    errorMessage: string,
    objectType: ObjectType,
    objectId: string,
    changes: Partial<ObjectTypeMap[typeof objectType]>,
    fn: (
      commandQueue: ReturnType<typeof useCommandQueueStore>
    ) => Promise<ApiResponse<T>>
  ): Promise<MutationResult<T>> {
    const pool = useObjectPoolStore()
    const pendingId = pool.addPending(objectType, objectId, changes)

    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      const response = await fn(commandQueue)
      return { queued: false, data: response.data }
    } catch (e) {
      if (e instanceof CommandQueuedError) {
        return { queued: true }
      }
      pool.removePending(pendingId)
      error.value = errorMessage
      throw e
    } finally {
      loading.value = false
    }
  }

  /**
   * Optimistic delete: removes the object from the pool, then fires the API call.
   * On success: object stays removed.
   * On queued: object stays removed.
   * On error: restores the object and rethrows.
   */
  async function destroy<T>(
    errorMessage: string,
    objectType: ObjectType,
    objectId: string,
    fn: (
      commandQueue: ReturnType<typeof useCommandQueueStore>
    ) => Promise<ApiResponse<T>>
  ): Promise<MutationResult<T>> {
    const pool = useObjectPoolStore()
    // Cascade-remove parent and all children, saving them for rollback
    const removedObjects = pool.cascadeRemove(objectType, objectId)

    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      const response = await fn(commandQueue)
      return { queued: false, data: response.data }
    } catch (e) {
      if (e instanceof CommandQueuedError) {
        return { queued: true }
      }
      // Restore each removed object into every scope it came from. For
      // objects with no recorded scopes (defensive — shouldn't happen if the
      // pool was consistent), derive a scope from the object itself.
      for (const entry of removedObjects) {
        const scopes = entry.scopes.length
          ? entry.scopes
          : [scopeForOptimisticObject(entry.object)]
        for (const scope of scopes) {
          pool.set(scope, entry.object)
        }
      }
      error.value = errorMessage
      throw e
    } finally {
      loading.value = false
    }
  }

  return { loading, error, mutate, create, update, destroy }
}
