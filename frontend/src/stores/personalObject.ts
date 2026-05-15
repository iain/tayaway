import type { PoolObject } from '@/types/pool'

// Personal objects belong to the user, not to any one workspace, and survive
// workspace switches so cross-workspace state (the workspace selector, your
// own membership in each workspace, your notification feed) stays coherent
// without having to re-sync on every switch.
export function isPersonalObject(
  obj: PoolObject,
  currentUserId: string | null
): boolean {
  if (obj.objectType === 'workspace') return true
  if (obj.objectType === 'notification') return true
  if (obj.objectType === 'member' && currentUserId) {
    return (obj as { userId: string }).userId === currentUserId
  }
  return false
}
