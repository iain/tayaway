import { openDB, type IDBPDatabase } from 'idb'
import type { RemovedEntry } from '@/stores/objectPool'
import type { ObjectType } from '@/types/pool'

// What to undo in the object pool if this command permanently fails on
// replay. Threaded into enqueue by useMutation and written atomically with
// the command row (a linkage registered after the fact leaves a window
// where a raced replay fails with nothing to roll back); consumed by
// processQueue's server-error path. Persisted so rollback still works when
// the replay happens after an app restart — pending overlays keep their
// ids across restarts via poolDb. Must be structured-cloneable: no Vue
// reactive proxies.
export type OptimisticRef =
  | { kind: 'create'; objectType: ObjectType; objectId: string }
  | {
      kind: 'update'
      objectType: ObjectType
      objectId: string
      pendingId: string
    }
  | { kind: 'destroy'; removed: RemovedEntry[] }

export interface StoredCommand {
  id: string
  method: 'POST' | 'PUT' | 'PATCH' | 'DELETE'
  path: string
  body?: unknown
  // The workspace the user was in when this command was enqueued. Carried
  // through replay so cross-workspace queued mutations don't get attributed
  // to whatever workspace happens to be active at the moment they go out.
  workspaceId?: string | null
  createdAt: number
  // Tie-breaker for commands enqueued in the same millisecond: createdAt
  // alone would leave their replay order to the random UUID primary key.
  // Session-scoped counter — across restarts createdAt always differs.
  // Absent on rows written before the field existed (sorts as 0).
  seq?: number
  // One ref per pool mutation this command made optimistically. Multi-
  // object flows (add date range = temp object + pending update on the
  // poll) link an array; all of it rolls back as one user change.
  optimistic?: OptimisticRef | OptimisticRef[]
}

interface CommandQueueDB {
  commands: {
    key: string
    value: StoredCommand
    indexes: { workspaceId: string }
  }
}

let dbPromise: Promise<IDBPDatabase<CommandQueueDB>> | null = null

function getDb(): Promise<IDBPDatabase<CommandQueueDB>> {
  if (!dbPromise) {
    dbPromise = openDB<CommandQueueDB>('tayaway-command-queue', 4, {
      upgrade(db, oldVersion, _newVersion, transaction) {
        if (oldVersion < 1) {
          db.createObjectStore('commands', { keyPath: 'id' })
        }
        if (oldVersion >= 1 && oldVersion < 2) {
          const store = transaction.objectStore('commands')
          if (store.indexNames.contains('status')) {
            store.deleteIndex('status')
          }
        }
        if (oldVersion < 3) {
          const store = transaction.objectStore('commands')
          if (!store.indexNames.contains('workspaceId')) {
            store.createIndex('workspaceId', 'workspaceId')
          }
        }
        if (oldVersion >= 1 && oldVersion < 4) {
          // getPendingCommands sorts in memory via byQueueOrder now (the
          // index couldn't express the seq tiebreak); drop the dead index
          // so nobody reaches for it and reintroduces random-tie ordering.
          const store = transaction.objectStore('commands')
          if (store.indexNames.contains('createdAt')) {
            store.deleteIndex('createdAt')
          }
        }
      },
    })
  }
  return dbPromise
}

let seqCounter = 0

export async function addCommand(
  command: Omit<StoredCommand, 'id' | 'createdAt' | 'seq'>
): Promise<string> {
  const db = await getDb()
  const id = crypto.randomUUID()
  const stored: StoredCommand = {
    ...command,
    id,
    createdAt: Date.now(),
    seq: ++seqCounter,
  }
  await db.add('commands', stored)
  return id
}

// Replay order: enqueue order. See StoredCommand.seq for why createdAt
// alone isn't enough.
export function byQueueOrder(a: StoredCommand, b: StoredCommand): number {
  return a.createdAt - b.createdAt || (a.seq ?? 0) - (b.seq ?? 0)
}

export async function removeCommand(id: string): Promise<void> {
  const db = await getDb()
  await db.delete('commands', id)
}

export async function getPendingCommands(): Promise<StoredCommand[]> {
  const db = await getDb()
  const commands = await db.getAll('commands')
  return commands.sort(byQueueOrder)
}

export async function count(): Promise<number> {
  const db = await getDb()
  return db.count('commands')
}

export async function clearAll(): Promise<void> {
  const db = await getDb()
  await db.clear('commands')
}
