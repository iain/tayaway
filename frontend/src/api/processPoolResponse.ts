import { useObjectPoolStore } from '@/stores'
import type { PoolObject, ObjectType } from '@/types/pool'

interface DeletedObject {
  objectType: ObjectType
  id: string
}

/**
 * Import pool objects and remove deletions from an API response body.
 *
 * Kept in its own module (rather than inside the API client) so the low-
 * level client stays pure and testable without a store mock, and so the
 * "server response hydrates the pool" behaviour is an explicit caller
 * choice rather than a hidden side effect of every request. The pool-
 * aware `api` wrapper in `@/api/client` calls this on GET responses, and
 * the command queue calls it on successful mutation replays.
 */
export function processPoolResponse(data: unknown): void {
  if (!data || typeof data !== 'object') return

  const pool = useObjectPoolStore()

  if (
    'objects' in data &&
    Array.isArray((data as { objects: unknown }).objects)
  ) {
    pool.importObjects((data as { objects: PoolObject[] }).objects)
  }

  if (
    'deleted' in data &&
    Array.isArray((data as { deleted: unknown }).deleted)
  ) {
    for (const item of (data as { deleted: DeletedObject[] }).deleted) {
      pool.remove(item.objectType, item.id)
    }
  }
}
