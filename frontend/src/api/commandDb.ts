import { openDB, type IDBPDatabase } from 'idb'

export interface StoredCommand {
  id: string
  method: 'POST' | 'PUT' | 'PATCH' | 'DELETE'
  path: string
  body?: unknown
  status: 'pending'
  createdAt: number
}

interface CommandQueueDB {
  commands: {
    key: string
    value: StoredCommand
    indexes: { status: string; createdAt: number }
  }
}

let dbPromise: Promise<IDBPDatabase<CommandQueueDB>> | null = null

function getDb(): Promise<IDBPDatabase<CommandQueueDB>> {
  if (!dbPromise) {
    dbPromise = openDB<CommandQueueDB>('tayaway-command-queue', 1, {
      upgrade(db) {
        const store = db.createObjectStore('commands', { keyPath: 'id' })
        store.createIndex('status', 'status')
        store.createIndex('createdAt', 'createdAt')
      },
    })
  }
  return dbPromise
}

export async function addCommand(
  command: Omit<StoredCommand, 'id' | 'status' | 'createdAt'>
): Promise<string> {
  const db = await getDb()
  const id = crypto.randomUUID()
  const stored: StoredCommand = {
    ...command,
    id,
    status: 'pending',
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
