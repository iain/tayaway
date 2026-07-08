import { describe, it, expect } from 'vitest'
import { positionBetween, positionForReorder } from './position'

describe('positionBetween', () => {
  it('slots into an empty list, before, after, and between', () => {
    expect(positionBetween(null, null)).toBe(1)
    expect(positionBetween(null, 5)).toBe(4)
    expect(positionBetween(5, null)).toBe(6)
    expect(positionBetween(2, 4)).toBe(3)
  })
})

describe('positionForReorder', () => {
  const positions = [1, 2, 3]

  it('moves an item up past its previous neighbour', () => {
    // middle up: land before position 2 → 0
    expect(positionForReorder(positions, 1, 'up')).toBe(0)
    // last up: land between 1 and 2 → 1.5
    expect(positionForReorder(positions, 2, 'up')).toBe(1.5)
  })

  it('moves an item down past its next neighbour', () => {
    // middle down: land after position 3 → 4
    expect(positionForReorder(positions, 1, 'down')).toBe(4)
    // first down: land between 2 and 3 → 2.5
    expect(positionForReorder(positions, 0, 'down')).toBe(2.5)
  })

  it('is a no-op at the ends', () => {
    expect(positionForReorder(positions, 0, 'up')).toBe(1)
    expect(positionForReorder(positions, 2, 'down')).toBe(3)
  })
})
