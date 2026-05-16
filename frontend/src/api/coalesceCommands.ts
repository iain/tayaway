import type { StoredCommand } from './commandDb'

export interface CoalescedCommand {
  method: 'POST' | 'PUT' | 'PATCH' | 'DELETE'
  path: string
  body?: unknown
  originalIds: string[]
  // The workspace the originating command(s) were enqueued in. Preserved so
  // the replay response lands in that workspace's scope rather than whatever
  // workspace the user happens to be looking at when the queue drains. Only
  // set when every merged command agreed on the same workspaceId; if they
  // disagreed (cross-workspace coalescing is not a real scenario today, but
  // belt-and-braces) we leave it undefined and let the response fall back
  // to the current workspace.
  workspaceId?: string | null
}

/**
 * Derive a resource key for a command. Commands with the same key target the
 * same resource and may be merged. Returns null for commands that cannot be
 * coalesced (e.g. action endpoints without an id).
 */
export function getResourceKey(command: StoredCommand): string | null {
  const { method, path, body } = command

  // PUT, PATCH, DELETE — the resource ID is already in the URL
  if (method === 'PUT' || method === 'PATCH' || method === 'DELETE') {
    return path
  }

  // POST — only coalescable if the body contains an id we can project
  if (method === 'POST' && body && typeof body === 'object' && 'id' in body) {
    const id = (body as { id: string }).id
    // Strip trailing slash, append the id to form the resource path
    const base = path.endsWith('/') ? path.slice(0, -1) : path
    return `${base}/${id}`
  }

  return null
}

type MergeEntry = CoalescedCommand | null

/**
 * Coalesce a FIFO-ordered list of stored commands into a reduced set by
 * merging commands that target the same resource.
 *
 * Merge rules (earlier × later):
 *   POST + PUT  → single POST with merged bodies
 *   POST + DELETE → both removed (cancelled out)
 *   PUT  + PUT  → single PUT with merged bodies
 *   PUT  + DELETE → DELETE only
 *   DELETE + POST/PUT → keep both in order (no merge)
 */
export function coalesceCommands(
  commands: StoredCommand[]
): CoalescedCommand[] {
  const result: MergeEntry[] = []
  const keyIndex = new Map<string, number>()

  for (const cmd of commands) {
    const key = getResourceKey(cmd)

    if (key === null) {
      // Non-coalescable — pass through as-is
      result.push(fromStored(cmd))
      continue
    }

    const existingIdx = keyIndex.get(key)
    const existing = existingIdx !== undefined ? result[existingIdx] : null

    if (!existing) {
      // First command for this resource key
      const idx = result.length
      result.push(fromStored(cmd))
      keyIndex.set(key, idx)
      continue
    }

    const earlierMethod = existing.method
    const laterMethod = cmd.method

    if (earlierMethod === 'DELETE') {
      // DELETE + anything → keep both in order, no merge
      const idx = result.length
      result.push(fromStored(cmd))
      keyIndex.set(key, idx)
      continue
    }

    if (earlierMethod === 'POST' && laterMethod === 'DELETE') {
      // POST + DELETE → cancel both
      existing.originalIds.push(cmd.id)
      result[existingIdx!] = null
      keyIndex.delete(key)
      continue
    }

    if (
      earlierMethod === 'POST' &&
      (laterMethod === 'PUT' || laterMethod === 'PATCH')
    ) {
      // POST + PUT/PATCH → merged POST
      existing.body = mergeBody(existing.body, cmd.body)
      existing.originalIds.push(cmd.id)
      existing.workspaceId = reconcileWorkspaceId(existing.workspaceId, cmd)
      continue
    }

    if (
      (earlierMethod === 'PUT' || earlierMethod === 'PATCH') &&
      (laterMethod === 'PUT' || laterMethod === 'PATCH')
    ) {
      // PUT + PUT → merged PUT (keep the later method)
      existing.method = laterMethod
      existing.body = mergeBody(existing.body, cmd.body)
      existing.originalIds.push(cmd.id)
      existing.workspaceId = reconcileWorkspaceId(existing.workspaceId, cmd)
      continue
    }

    if (
      (earlierMethod === 'PUT' || earlierMethod === 'PATCH') &&
      laterMethod === 'DELETE'
    ) {
      // PUT + DELETE → DELETE only
      existing.method = 'DELETE'
      existing.path = cmd.path
      existing.body = cmd.body
      existing.originalIds.push(cmd.id)
      existing.workspaceId = reconcileWorkspaceId(existing.workspaceId, cmd)
      continue
    }

    // Fallback: keep both in order
    const idx = result.length
    result.push(fromStored(cmd))
    keyIndex.set(key, idx)
  }

  return result.filter((entry): entry is CoalescedCommand => entry !== null)
}

function fromStored(cmd: StoredCommand): CoalescedCommand {
  return {
    method: cmd.method,
    path: cmd.path,
    body: cmd.body,
    originalIds: [cmd.id],
    workspaceId: cmd.workspaceId ?? null,
  }
}

// Two merged commands must agree on the workspace they target for the
// resulting replay to be unambiguously attributable. Disagreement falls
// back to undefined so processPoolResponse uses the current workspace —
// not ideal, but better than picking one arbitrarily.
function reconcileWorkspaceId(
  earlier: string | null | undefined,
  later: StoredCommand
): string | null | undefined {
  const laterWs = later.workspaceId ?? null
  if (earlier === undefined) return laterWs
  if (earlier === laterWs) return earlier
  return undefined
}

function mergeBody(earlier: unknown, later: unknown): unknown {
  if (
    earlier &&
    typeof earlier === 'object' &&
    !Array.isArray(earlier) &&
    later &&
    typeof later === 'object' &&
    !Array.isArray(later)
  ) {
    return { ...earlier, ...later }
  }
  // If either isn't a plain object, later wins
  return later ?? earlier
}
