import type { PoolTaskList } from '@/types/pool'
import { byPositionOrder } from './positionOrder'

const byListOrder = byPositionOrder<PoolTaskList>((list) => list.name)

/**
 * Order task lists by position with deterministic tie-breaks so every
 * client renders the same order (see `byPositionOrder`).
 */
export function sortTaskLists(lists: PoolTaskList[]): PoolTaskList[] {
  return [...lists].sort(byListOrder)
}
