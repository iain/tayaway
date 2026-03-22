import { ref } from 'vue'
import { useCommandQueueStore, CommandQueuedError } from '@/stores/commandQueue'
import { useObjectPoolStore } from '@/stores/objectPool'
import type { ApiResponse } from '@/api/client'
import type { ObjectType, ObjectTypeMap } from '@/types/pool'

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
    pool.set(tempObject, { isTemp: true })

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
      // Restore all removed objects on error
      for (const obj of removedObjects) {
        pool.set(obj)
      }
      error.value = errorMessage
      throw e
    } finally {
      loading.value = false
    }
  }

  return { loading, error, mutate, create, update, destroy }
}
