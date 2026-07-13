import type { PoolTaskItem } from '@/types/pool'
import { byPositionOrder } from './positionOrder'

const EMPTY: ReadonlySet<string> = new Set()

const byItemOrder = byPositionOrder<PoolTaskItem>((item) => item.content)

/**
 * Order task items by position, with completed items sunk to the bottom so the
 * active list stays uncluttered.
 *
 * `heldIds` are items the user *just* checked off and that are being held in
 * place for a moment before they animate down — they sort as if incomplete so
 * they don't jump out from under the finger. Remote toggles and already-settled
 * completions aren't held, so they sink immediately.
 */
export function sortTaskItems(
  items: PoolTaskItem[],
  heldIds: ReadonlySet<string> = EMPTY
): PoolTaskItem[] {
  const sunk = (item: PoolTaskItem): number =>
    item.completedAt !== null && !heldIds.has(item.id) ? 1 : 0

  return [...items].sort((a, b) => {
    const diff = sunk(a) - sunk(b)
    return diff !== 0 ? diff : byItemOrder(a, b)
  })
}
