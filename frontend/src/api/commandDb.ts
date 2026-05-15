import { openDB, type IDBPDatabase } from 'idb'

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

export async function addCommand(
  command: Omit<StoredCommand, 'id' | 'createdAt'>
): Promise<string> {
  const db = await getDb()
  const id = crypto.randomUUID()
  const stored: StoredCommand = {
    ...command,
    id,
    createdAt: Date.now(),
  }
  await db.add('commands', stored)
  return id
}

export async function removeCommand(id: string): Promise<void> {
  const db = await getDb()
  await db.delete('commands', id)
}

export async function getPendingCommands(): Promise<StoredCommand[]> {
  const db = await getDb()
  return db.getAllFromIndex('commands', 'createdAt')
}

export async function count(): Promise<number> {
  const db = await getDb()
  return db.count('commands')
}

export async function clearAll(): Promise<void> {
  const db = await getDb()
  await db.clear('commands')
}
