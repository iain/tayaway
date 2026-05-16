import { useObjectPoolStore } from '@/stores'
import { useWorkspaceStore } from '@/stores/workspace'
import { workspaceScope } from '@/api/poolDb'
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
 *
 * REST responses are tagged with the workspace's scope — that's the
 * channel the matching WebSocket broadcasts will arrive on, so the REST-
 * delivered copy and the WS-delivered copy share a scope. Callers that
 * know the originating workspace (api.get snapshots it at request time;
 * the command queue carries the workspaceId the command was enqueued in)
 * pass `scope` explicitly so a workspace switch mid-flight doesn't
 * misroute the response. Without an explicit scope we fall back to the
 * current workspace.
 *
 * Endpoints that deliver personal data (notifications) bypass this path
 * and route through rawApi + an explicit pool.importObjects(PERSONAL_SCOPE).
 */
export function processPoolResponse(data: unknown, scope?: string): void {
  if (!data || typeof data !== 'object') return

  const pool = useObjectPoolStore()
  const resolvedScope = scope ?? defaultScope()

  if ('objects' in data && Array.isArray((data as { objects: unknown }).objects)) {
    const objects = (data as { objects: PoolObject[] }).objects
    if (resolvedScope) {
      pool.importObjects(objects, { scope: resolvedScope })
    } else if (objects.length > 0) {
      // No active workspace and no explicit scope — dropping the payload
      // silently would hide bugs (e.g. a REST call firing before
      // initialization completes). Log so this doesn't disappear.
      console.warn(
        `[processPoolResponse] dropping ${objects.length} pool object(s): no workspace scope available`
      )
    }
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

function defaultScope(): string | null {
  const wsId = useWorkspaceStore().currentWorkspaceId
  return wsId ? workspaceScope(wsId) : null
}
