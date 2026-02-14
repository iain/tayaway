import { openDB, type IDBPDatabase } from 'idb'
import type { PoolObject, ObjectType } from '@/types/pool'

interface StoredObject {
  key: string
  objectType: ObjectType
  id: string
  data: PoolObject
}

interface MetaEntry {
  key: string
  workspaceId: string
}

interface PoolCacheDB {
  objects: {
    key: string
    value: StoredObject
    indexes: { objectType: ObjectType }
  }
  meta: {
    key: string
    value: MetaEntry
  }
}

let dbPromise: Promise<IDBPDatabase<PoolCacheDB>> | null = null

function getDb(): Promise<IDBPDatabase<PoolCacheDB>> {
  if (!dbPromise) {
    dbPromise = openDB<PoolCacheDB>('tayaway-pool-cache', 1, {
      upgrade(db) {
        const store = db.createObjectStore('objects', { keyPath: 'key' })
        store.createIndex('objectType', 'objectType')
        db.createObjectStore('meta', { keyPath: 'key' })
      },
    })
  }
  return dbPromise
}

function toKey(objectType: string, id: string): string {
  return `${objectType}:${id}`
}

export async function saveObjects(objects: PoolObject[]): Promise<void> {
  if (objects.length === 0) return
  const db = await getDb()
  const tx = db.transaction('objects', 'readwrite')
  for (const obj of objects) {
    const stored: StoredObject = {
      key: toKey(obj.objectType, obj.id),
      objectType: obj.objectType,
      id: obj.id,
      data: obj,
    }
    tx.store.put(stored)
  }
  await tx.done
}

export async function removeObjects(
  entries: { objectType: string; id: string }[]
): Promise<void> {
  if (entries.length === 0) return
  const db = await getDb()
  const tx = db.transaction('objects', 'readwrite')
  for (const entry of entries) {
    tx.store.delete(toKey(entry.objectType, entry.id))
  }
  await tx.done
}

export async function replaceAll(
  workspaceId: string,
  objects: PoolObject[]
): Promise<void> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta'], 'readwrite')
  tx.objectStore('objects').clear()
  tx.objectStore('meta').put({ key: 'workspace', workspaceId })
  const objectStore = tx.objectStore('objects')
  for (const obj of objects) {
    objectStore.put({
      key: toKey(obj.objectType, obj.id),
      objectType: obj.objectType,
      id: obj.id,
      data: obj,
    })
  }
  await tx.done
}

export async function loadAll(): Promise<{
  workspaceId: string | null
  objects: PoolObject[]
}> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta'], 'readonly')
  const meta = await tx.objectStore('meta').get('workspace')
  const stored = await tx.objectStore('objects').getAll()
  return {
    workspaceId: meta?.workspaceId ?? null,
    objects: stored.map((s) => s.data),
  }
}

export async function clearAll(): Promise<void> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta'], 'readwrite')
  tx.objectStore('objects').clear()
  tx.objectStore('meta').clear()
  await tx.done
}
