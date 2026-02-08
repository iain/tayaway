import { computed, type ComputedRef } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import type { ObjectType, ObjectTypeMap } from '@/types/pool'

/**
 * Composable for reactive access to a single pool object.
 *
 * @example
 * const { object, isPending } = usePoolObject('event', eventId)
 * // object.value is the event with pending updates merged
 * // isPending.value is true if there are pending optimistic updates
 */
export function usePoolObject<T extends ObjectType>(
  objectType: T,
  id: ComputedRef<string> | string
): {
  object: ComputedRef<ObjectTypeMap[T] | undefined>
  isPending: ComputedRef<boolean>
} {
  const pool = useObjectPoolStore()

  const resolvedId = computed(() => (typeof id === 'string' ? id : id.value))

  const object = computed(() => pool.get(objectType, resolvedId.value))

  const isPending = computed(() =>
    pool.hasPending(objectType, resolvedId.value)
  )

  return {
    object,
    isPending,
  }
}

/**
 * Composable for reactive access to multiple pool objects by IDs.
 *
 * @example
 * const { objects } = usePoolObjects('dateRange', dateRangeIds)
 */
export function usePoolObjects<T extends ObjectType>(
  objectType: T,
  ids: ComputedRef<string[]> | string[]
): {
  objects: ComputedRef<ObjectTypeMap[T][]>
} {
  const pool = useObjectPoolStore()

  const resolvedIds = computed(() => (Array.isArray(ids) ? ids : ids.value))

  const objects = computed(() => pool.getMany(objectType, resolvedIds.value))

  return {
    objects,
  }
}
