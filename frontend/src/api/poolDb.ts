import { openDB, type IDBPDatabase } from 'idb'
import type { PoolObject, ObjectType, PendingUpdate } from '@/types/pool'
import { Scope } from '@/api/scope'

interface StoredObject {
  key: string
  scope: Scope
  objectType: ObjectType
  id: string
  data: PoolObject
}

interface StoredPendingEntry {
  key: string
  updates: PendingUpdate[]
}

interface MetaEntry {
  key: string
  syncedAt?: string
  cacheVersion?: number
}

interface PoolCacheDB {
  objects: {
    key: string
    value: StoredObject
    indexes: { scope: string; scopeAndType: [string, ObjectType] }
  }
  meta: {
    key: string
    value: MetaEntry
  }
  pendingUpdates: {
    key: string
    value: StoredPendingEntry
  }
}

// Bump this when the sync protocol changes to invalidate stale caches.
// Bumped to 11 when the cache became multi-workspace; old caches lack the
// scope field and must be wiped on upgrade.
// Bumped to 12 when chores gained a `time` field; old cached chores lack it.
// Bumped to 13 when events and workspaces gained a `timezone` field.
// Bumped to 14 when rsvps gained an `attendance` day-set field.
// Bumped to 15 when attendance entries gained per-day `{date, plusOnes}` guests.
// Bumped to 16 when per-scope `fullSyncedAt` meta was added for the
// reconciliation cadence (wipe → one full sync that records it).
const CACHE_VERSION = 16

const CACHE_VERSION_META_KEY = 'cacheVersion'
const SYNCED_AT_META_PREFIX = 'syncedAt:'
// Last *full* sync per scope — the reconciliation cadence only trusts the
// partial-sync cursor while this is fresh.
const FULL_SYNCED_AT_META_PREFIX = 'fullSyncedAt:'

let dbPromise: Promise<IDBPDatabase<PoolCacheDB>> | null = null

function getDb(): Promise<IDBPDatabase<PoolCacheDB>> {
  if (!dbPromise) {
    dbPromise = openDB<PoolCacheDB>('tayaway-pool-cache', 4, {
      upgrade(db, oldVersion, _newVersion, tx) {
        if (oldVersion < 1) {
          const store = db.createObjectStore('objects', { keyPath: 'key' })
          store.createIndex('objectType', 'objectType')
          db.createObjectStore('meta', { keyPath: 'key' })
        }
        if (oldVersion < 2) {
          db.createObjectStore('pendingUpdates', { keyPath: 'key' })
        }
        if (oldVersion < 3) {
          // Multi-workspace cache: old entries lack `scope` and use a
          // non-scoped key format. Wipe them and create the new index.
          const objectsStore = tx.objectStore('objects')
          objectsStore.clear()
          objectsStore.createIndex('scope', 'scope')
          tx.objectStore('meta').clear()
          tx.objectStore('pendingUpdates').clear()
        }
        if (oldVersion < 4) {
          // Hydration loads one (scope, objectType) bucket at a time; the
          // standalone `objectType` index would force a full-scope scan
          // plus filter. Replace it with a compound index so each load
          // is a single tight seek.
          const objectsStore = tx.objectStore('objects')
          if (objectsStore.indexNames.contains('objectType')) {
            objectsStore.deleteIndex('objectType')
          }
          objectsStore.createIndex('scopeAndType', ['scope', 'objectType'])
        }
      },
    })
  }
  return dbPromise
}

function toKey(scope: Scope, objectType: string, id: string): string {
  return `${scope}::${objectType}:${id}`
}

export async function saveObjects(
  scope: Scope,
  objects: PoolObject[]
): Promise<void> {
  if (objects.length === 0) return
  const db = await getDb()
  const tx = db.transaction('objects', 'readwrite')
  for (const obj of objects) {
    tx.store.put({
      key: toKey(scope, obj.objectType, obj.id),
      scope,
      objectType: obj.objectType,
      id: obj.id,
      data: obj,
    })
  }
  await tx.done
}

export async function removeObjects(
  scope: Scope,
  entries: { objectType: string; id: string }[]
): Promise<void> {
  if (entries.length === 0) return
  const db = await getDb()
  const tx = db.transaction('objects', 'readwrite')
  for (const entry of entries) {
    tx.store.delete(toKey(scope, entry.objectType, entry.id))
  }
  await tx.done
}

export async function savePendingUpdates(
  entries: Map<string, PendingUpdate[]>
): Promise<void> {
  const db = await getDb()
  const tx = db.transaction('pendingUpdates', 'readwrite')
  tx.store.clear()
  for (const [key, updates] of entries) {
    tx.store.put({ key, updates })
  }
  await tx.done
}

export async function loadPendingUpdates(): Promise<
  Map<string, PendingUpdate[]>
> {
  const db = await getDb()
  const stored = await db.getAll('pendingUpdates')
  const map = new Map<string, PendingUpdate[]>()
  for (const entry of stored) {
    map.set(entry.key, entry.updates)
  }
  return map
}

/**
 * Replace one scope's objects atomically. Other scopes (other workspaces,
 * personal data) are left alone so a workspace full-sync doesn't wipe the
 * caches we want to keep hot.
 */
export async function replaceScope(
  scope: Scope,
  objects: PoolObject[],
  syncedAt?: string,
  fullSyncedAt?: string
): Promise<void> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta'], 'readwrite')

  const objectStore = tx.objectStore('objects')
  const scopeIndex = objectStore.index('scope')
  let cursor = await scopeIndex.openCursor(IDBKeyRange.only(scope))
  while (cursor) {
    cursor.delete()
    cursor = await cursor.continue()
  }

  for (const obj of objects) {
    objectStore.put({
      key: toKey(scope, obj.objectType, obj.id),
      scope,
      objectType: obj.objectType,
      id: obj.id,
      data: obj,
    })
  }

  tx.objectStore('meta').put({
    key: CACHE_VERSION_META_KEY,
    cacheVersion: CACHE_VERSION,
  })
  if (syncedAt) {
    tx.objectStore('meta').put({
      key: `${SYNCED_AT_META_PREFIX}${scope}`,
      syncedAt,
    })
  }
  if (fullSyncedAt) {
    tx.objectStore('meta').put({
      key: `${FULL_SYNCED_AT_META_PREFIX}${scope}`,
      syncedAt: fullSyncedAt,
    })
  }
  await tx.done
}

export async function clearScope(scope: Scope): Promise<void> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta'], 'readwrite')
  const scopeIndex = tx.objectStore('objects').index('scope')
  let cursor = await scopeIndex.openCursor(IDBKeyRange.only(scope))
  while (cursor) {
    cursor.delete()
    cursor = await cursor.continue()
  }
  tx.objectStore('meta').delete(`${SYNCED_AT_META_PREFIX}${scope}`)
  tx.objectStore('meta').delete(`${FULL_SYNCED_AT_META_PREFIX}${scope}`)
  await tx.done
}

/**
 * Read only the lightweight metadata record from the cache.
 * Returns the cache version and a per-scope syncedAt map (so a partial sync
 * per workspace can use its own cursor). The active workspace lives in
 * localStorage; IDB doesn't track it. The map's keys are best-effort parsed
 * into Scope — meta records persist across schema changes and the parser
 * skips anything it doesn't recognise.
 */
export async function loadMeta(): Promise<{
  cacheVersion: number | null
  syncedAt: Map<Scope, string>
  fullSyncedAt: Map<Scope, string>
}> {
  const db = await getDb()
  const tx = db.transaction('meta', 'readonly')
  const all = await tx.store.getAll()
  let cacheVersion: number | null = null
  const syncedAt = new Map<Scope, string>()
  const fullSyncedAt = new Map<Scope, string>()
  for (const entry of all) {
    if (entry.key === CACHE_VERSION_META_KEY) {
      cacheVersion = entry.cacheVersion ?? null
    } else if (
      entry.key.startsWith(FULL_SYNCED_AT_META_PREFIX) &&
      entry.syncedAt
    ) {
      const scope = Scope.parse(
        entry.key.slice(FULL_SYNCED_AT_META_PREFIX.length)
      )
      if (scope) fullSyncedAt.set(scope, entry.syncedAt)
    } else if (entry.key.startsWith(SYNCED_AT_META_PREFIX) && entry.syncedAt) {
      const scope = Scope.parse(entry.key.slice(SYNCED_AT_META_PREFIX.length))
      if (scope) syncedAt.set(scope, entry.syncedAt)
    }
  }
  return { cacheVersion, syncedAt, fullSyncedAt }
}

/**
 * Read all cached objects of a single object type from a single scope.
 * Callers should yield to the event loop between successive type loads so the
 * browser can paint frames while the cache is being restored progressively.
 */
export async function loadObjectsByType(
  scope: Scope,
  objectType: ObjectType
): Promise<PoolObject[]> {
  const db = await getDb()
  const tx = db.transaction('objects', 'readonly')
  const stored = await tx.store
    .index('scopeAndType')
    .getAll(IDBKeyRange.only([scope, objectType]))
  return stored.map((s) => s.data)
}

/**
 * Read all pending updates from the cache.
 */
export async function loadPendingUpdatesFromDb(): Promise<
  Map<string, PendingUpdate[]>
> {
  const db = await getDb()
  const stored = await db.getAll('pendingUpdates')
  const map = new Map<string, PendingUpdate[]>()
  for (const entry of stored) {
    map.set(entry.key, entry.updates)
  }
  return map
}

export { CACHE_VERSION }

export async function saveSyncedAt(
  scope: Scope,
  syncedAt: string
): Promise<void> {
  const db = await getDb()
  await db.put('meta', {
    key: `${SYNCED_AT_META_PREFIX}${scope}`,
    syncedAt,
  })
}

export async function clearAll(): Promise<void> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta', 'pendingUpdates'], 'readwrite')
  tx.objectStore('objects').clear()
  tx.objectStore('meta').clear()
  tx.objectStore('pendingUpdates').clear()
  await tx.done
}
