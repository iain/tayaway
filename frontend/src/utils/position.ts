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

/**
 * Computes the position that moves the item at `index` one step in `direction`,
 * hopping it past its immediate neighbour. `positions` is the current ordering.
 * Returns the item's existing position (a no-op) when it's already at that end.
 */
export function positionForReorder(
  positions: number[],
  index: number,
  direction: 'up' | 'down'
): number {
  if (direction === 'up') {
    if (index <= 0) return positions[index]!
    return positionBetween(positions[index - 2] ?? null, positions[index - 1]!)
  }
  if (index >= positions.length - 1) return positions[index]!
  return positionBetween(positions[index + 1]!, positions[index + 2] ?? null)
}
