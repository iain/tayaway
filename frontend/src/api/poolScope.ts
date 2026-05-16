import { useWorkspaceStore } from '@/stores/workspace'
import { workspaceScope } from '@/api/poolDb'

/**
 * Resolve the current workspace's pool scope, or throw if no workspace is
 * active. Mutations that create scope-less objects (date ranges, votes,
 * expense participants, etc.) call this to tag their optimistic writes —
 * the resulting scope must match the channel the server confirmation will
 * arrive on, so guessing here would silently misroute data.
 */
export function currentWorkspaceScopeOrThrow(): string {
  const wsId = useWorkspaceStore().currentWorkspaceId
  if (!wsId) {
    throw new Error(
      'currentWorkspaceScopeOrThrow: no active workspace — mutations require a workspace context'
    )
  }
  return workspaceScope(wsId)
}
