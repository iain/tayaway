import type { PoolObject, ObjectType } from './pool'

/** Reference to an object that's been deleted on the server. */
export interface DeletedObject {
  objectType: ObjectType
  id: string
}

/**
 * Neutral shape passed to `pool.applyUpdate()`. Consumers (the WebSocket
 * sync/broadcast handlers, anything else that wants to merge a batch of
 * server changes into the local pool) produce this from their incoming
 * message and hand it over, instead of reaching into the pool store's
 * individual methods (importObjects, cascadeRemove, replaceObjects). That
 * way the WebSocket protocol and the pool API evolve independently.
 *
 * - `replace`: authoritative full sync from the server. The pool clears
 *   everything except temp/pending state and re-fills from `objects`.
 * - `merge`: incremental update. New or updated objects in `objects` are
 *   imported; refs in `deleted` are cascade-removed.
 */
export type PoolUpdate =
  | { kind: 'replace'; objects: PoolObject[] }
  | { kind: 'merge'; objects?: PoolObject[]; deleted?: DeletedObject[] }
