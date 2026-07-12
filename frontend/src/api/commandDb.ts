import { openDB, type IDBPDatabase } from 'idb'
import type { RemovedEntry } from '@/stores/objectPool'
import type { ObjectType } from '@/types/pool'

// What to undo in the object pool if this command permanently fails on
// replay. Registered by useMutation when a command gets queued (direct
// success/error paths roll back inline and never register one); consumed
// by processQueue's server-error path. Persisted on the command row so
// rollback still works when the replay happens after an app restart —
// pending overlays keep their ids across restarts via poolDb.
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
  optimistic?: OptimisticRef
}

interface CommandQueueDB {
  commands: {
    key: string
    value: StoredCommand
    indexes: { createdAt: number; workspaceId: string }
  }
}

let dbPromise: Promise<IDBPDatabase<CommandQueueDB>> | null = null

function getDb(): Promise<IDBPDatabase<CommandQueueDB>> {
  if (!dbPromise) {
    dbPromise = openDB<CommandQueueDB>('tayaway-command-queue', 3, {
      upgrade(db, oldVersion, _newVersion, transaction) {
        if (oldVersion < 1) {
          const store = db.createObjectStore('commands', { keyPath: 'id' })
          store.createIndex('createdAt', 'createdAt')
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

// Attach rollback info to an already-stored command. Registered after the
// fact (the command row is written before the request is attempted, but
// only queued outcomes need rollback), so the row may already be gone if a
// replay raced us — that's a no-op, matching today's behaviour.
export async function setOptimistic(
  id: string,
  optimistic: OptimisticRef
): Promise<void> {
  const db = await getDb()
  const tx = db.transaction('commands', 'readwrite')
  const stored = await tx.store.get(id)
  if (stored) {
    await tx.store.put({ ...stored, optimistic })
  }
  await tx.done
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
