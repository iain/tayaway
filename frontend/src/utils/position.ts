/**
 * Computes a float position value between two neighboring positions.
 * Used to reorder items without renumbering all positions.
 */
export function positionBetween(
  before: number | null,
  after: number | null
): number {
  if (before === null && after === null) return 1.0
  if (before === null) return after! - 1.0
  if (after === null) return before + 1.0
  return (before + after) / 2
}
