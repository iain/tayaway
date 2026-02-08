import { useObjectPoolStore } from '@/stores/objectPool'
import type { ObjectType, ObjectTypeMap, PoolObject } from '@/types/pool'
import type { ApiResponse } from '@/api/client'

// Response type that includes pool objects
interface PoolResponse {
  objects: PoolObject[]
}

/**
 * Composable for optimistic updates with automatic rollback.
 *
 * @example
 * const { execute } = useOptimistic()
 *
 * // Optimistically update a vote
 * await execute(
 *   'vote',
 *   voteId,
 *   { response: 'yes' },
 *   () => api.post(`/events/${eventId}/votes`, { date_range_id: dateRangeId, response: 'yes' })
 * )
 */
export function useOptimistic() {
  const pool = useObjectPoolStore()

  /**
   * Execute an optimistic update.
   *
   * 1. Apply changes immediately to the pool (pending state)
   * 2. Execute the API call
   * 3. On success: import server response (clears pending)
   * 4. On failure: remove pending changes (rollback)
   *
   * @param objectType - The type of object being updated
   * @param objectId - The ID of the object
   * @param optimisticChanges - Changes to apply immediately
   * @param apiCall - Function that performs the API call
   * @returns The API response data
   */
  async function execute<T extends ObjectType, R extends PoolResponse>(
    objectType: T,
    objectId: string,
    optimisticChanges: Partial<ObjectTypeMap[T]>,
    apiCall: () => Promise<ApiResponse<R>>
  ): Promise<R> {
    const pendingId = pool.addPending(objectType, objectId, optimisticChanges)

    try {
      const result = await apiCall()
      // Server response is automatically imported by API client, which clears pending
      return result.data
    } catch (error) {
      // Rollback on failure
      pool.removePending(pendingId)
      throw error
    }
  }

  /**
   * Execute an optimistic create operation.
   *
   * For creating new objects, we add the full object to the pool optimistically,
   * then replace it with the server version on success.
   *
   * @param tempObject - The temporary object to add
   * @param apiCall - Function that performs the API call
   * @returns The API response data
   */
  async function executeCreate<T extends ObjectType, R extends PoolResponse>(
    tempObject: ObjectTypeMap[T],
    apiCall: () => Promise<ApiResponse<R>>
  ): Promise<R> {
    // Add temp object to pool
    pool.set(tempObject)

    try {
      const result = await apiCall()
      // Server response is automatically imported by API client, replacing temp object
      return result.data
    } catch (error) {
      // Rollback - remove temp object
      pool.remove(tempObject.objectType, tempObject.id)
      throw error
    }
  }

  /**
   * Execute an optimistic delete operation.
   *
   * The object is removed immediately, then restored on failure.
   *
   * @param objectType - The type of object being deleted
   * @param objectId - The ID of the object
   * @param apiCall - Function that performs the API call
   */
  async function executeDelete<T extends ObjectType, R = unknown>(
    objectType: T,
    objectId: string,
    apiCall: () => Promise<ApiResponse<R>>
  ): Promise<R> {
    // Save current state for potential rollback
    const currentObject = pool.getServer(objectType, objectId)

    // Optimistically remove
    pool.remove(objectType, objectId)

    try {
      const result = await apiCall()
      return result.data
    } catch (error) {
      // Rollback - restore the object
      if (currentObject) {
        pool.set(currentObject)
      }
      throw error
    }
  }

  return {
    execute,
    executeCreate,
    executeDelete,
  }
}
