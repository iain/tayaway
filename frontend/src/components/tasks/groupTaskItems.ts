import type { PoolTaskItem } from '@/types/pool'
import { sortTaskItems } from './sortTaskItems'

// How long a completed item stays in the visible completed zone before it
// moves down into the History section. Long enough that a mid-shopping-trip
// "wait, did I grab that?" glance still finds it; short enough that the list
// doesn't silt up over days of use.
export const HISTORY_AFTER_MS = 60 * 60 * 1000

const EMPTY: ReadonlySet<string> = new Set()

/**
 * An item belongs in History once it has been completed for more than
 * HISTORY_AFTER_MS. `now` is passed in (rather than read from the clock) so
 * consumers drive it from the shared minute ticker and items migrate to
 * History reactively as time passes.
 */
export function isHistoryItem(item: PoolTaskItem, now: number): boolean {
  if (item.completedAt === null) return false
  return now - Date.parse(item.completedAt) >= HISTORY_AFTER_MS
}

export interface GroupedTaskItems {
  /** Active items plus recently-completed ones, in display order. */
  current: PoolTaskItem[]
  /** Items completed over an hour ago, newest completion first. */
  history: PoolTaskItem[]
}

/**
 * Split a list's items into the visible list and the History section.
 *
 * The current group keeps the existing ordering rules (`sortTaskItems`):
 * active items by position, recently-completed items sunk to the bottom,
 * held items pinned in place. History is ordered by completion time, newest
 * first, so the top of History reads as "what just aged out".
 */
export function groupTaskItems(
  items: PoolTaskItem[],
  now: number,
  heldIds: ReadonlySet<string> = EMPTY
): GroupedTaskItems {
  const current: PoolTaskItem[] = []
  const history: PoolTaskItem[] = []
  for (const item of items) {
    if (isHistoryItem(item, now)) {
      history.push(item)
    } else {
      current.push(item)
    }
  }
  // Serializer timestamps share one ISO-8601 format, so lexicographic order
  // is chronological order — no need to re-parse inside the comparator.
  // Ties (a bulk sync stamping several completions alike) break by id so
  // every client renders the same order.
  history.sort((a, b) => {
    if (a.completedAt !== b.completedAt) {
      return a.completedAt! < b.completedAt! ? 1 : -1
    }
    return a.id < b.id ? -1 : 1
  })
  return { current: sortTaskItems(current, heldIds), history }
}
