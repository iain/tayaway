import { ref } from 'vue'
import { useCommandQueueStore, CommandQueuedError } from '@/stores/commandQueue'
import { useObjectPoolStore } from '@/stores/objectPool'
import type { OptimisticRef } from '@/api/commandDb'
import type { ApiResponse } from '@/api/client'
import type { ObjectType, ObjectTypeMap } from '@/types/pool'

/**
 * The slice of the command queue handed to mutation callbacks. create/
 * update/destroy wrap the real store so enqueue carries the rollback
 * linkage — persisting it atomically with the command row closes the
 * window where a raced replay could permanently fail before a separately
 * registered linkage landed, stranding the optimistic state forever.
 */
export interface CommandEnqueuer {
  enqueue<T>(
    method: 'POST' | 'PUT' | 'PATCH' | 'DELETE',
    path: string,
    body?: unknown
  ): Promise<ApiResponse<T>>
}

function withOptimistic(
  queue: ReturnType<typeof useCommandQueueStore>,
  optimistic: OptimisticRef | OptimisticRef[]
): CommandEnqueuer {
  return {
    enqueue: (method, path, body) =>
      queue.enqueue(method, path, body, optimistic),
  }
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
    fn: (commandQueue: CommandEnqueuer) => Promise<ApiResponse<T>>
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
   *
   * Accepts an array when one command creates several objects at once (an
   * attendance plus its inline guest) — all temps are inserted before the
   * call and all roll back together on a hard error.
   */
  async function create<T>(
    errorMessage: string,
    tempObject: ObjectTypeMap[ObjectType] | ObjectTypeMap[ObjectType][],
    fn: (commandQueue: CommandEnqueuer) => Promise<ApiResponse<T>>
  ): Promise<MutationResult<T>> {
    const pool = useObjectPoolStore()
    const temps = Array.isArray(tempObject) ? tempObject : [tempObject]
    for (const temp of temps) {
      pool.set(temp, { isTemp: true })
    }

    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      const refs = temps.map(
        (temp): OptimisticRef => ({
          kind: 'create',
          objectType: temp.objectType,
          objectId: temp.id,
        })
      )
      const response = await fn(
        withOptimistic(commandQueue, refs.length === 1 ? refs[0]! : refs)
      )
      return { queued: false, data: response.data }
    } catch (e) {
      if (e instanceof CommandQueuedError) {
        return { queued: true }
      }
      for (const temp of temps) {
        pool.cascadeRemove(temp.objectType, temp.id)
      }
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
    fn: (commandQueue: CommandEnqueuer) => Promise<ApiResponse<T>>
  ): Promise<MutationResult<T>> {
    const pool = useObjectPoolStore()
    const pendingId = pool.addPending(objectType, objectId, changes)

    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      const response = await fn(
        withOptimistic(commandQueue, {
          kind: 'update',
          objectType,
          objectId,
          pendingId,
        })
      )
      // The response import (inside the command queue) only clears overlays
      // the server timestamp postdates — a client clock running ahead of the
      // server defeats that, leaving a stale overlay that masks other users'
      // edits. A direct success IS the confirmation of this change, so drop
      // the overlay explicitly. No-op when the import already cleared it.
      pool.removePending(pendingId)
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
    fn: (commandQueue: CommandEnqueuer) => Promise<ApiResponse<T>>
  ): Promise<MutationResult<T>> {
    const pool = useObjectPoolStore()
    // Cascade-remove parent and all children, saving them for rollback
    const removedObjects = pool.cascadeRemove(objectType, objectId)

    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      const response = await fn(
        withOptimistic(commandQueue, {
          kind: 'destroy',
          removed: removedObjects,
        })
      )
      return { queued: false, data: response.data }
    } catch (e) {
      if (e instanceof CommandQueuedError) {
        return { queued: true }
      }
      // Restore each removed object to every scope it came from. The pool
      // tracks scope membership per object, so callers don't have to.
      pool.restore(removedObjects)
      error.value = errorMessage
      throw e
    } finally {
      loading.value = false
    }
  }

  return { loading, error, mutate, create, update, destroy }
}
