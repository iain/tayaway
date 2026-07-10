import type { PoolChore } from '@/types/pool'

/**
 * Whether the chores page should nudge the user toward auto-fill: the roster
 * has seats and fewer than half of them are filled. Fills in either direction
 * (auto-fill or by hand) make the nudge disappear on its own, so it needs no
 * dismissal state.
 */
export function shouldSuggestAutofill(
  chores: ReadonlyArray<Pick<PoolChore, 'peoplePerDay'>>,
  dateCount: number,
  assignmentCount: number
): boolean {
  const seatsPerDay = chores.reduce((sum, c) => sum + c.peoplePerDay, 0)
  const totalSeats = seatsPerDay * dateCount
  return assignmentCount * 2 < totalSeats
}
