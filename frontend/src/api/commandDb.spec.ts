import { describe, it, expect } from 'vitest'
import { byQueueOrder, type StoredCommand } from './commandDb'

function cmd(
  overrides: Partial<StoredCommand> & { id: string }
): StoredCommand {
  return {
    method: 'POST',
    path: '/api/events',
    createdAt: 1,
    ...overrides,
  }
}

describe('byQueueOrder', () => {
  // createdAt has millisecond resolution, so two rapid mutations can share a
  // timestamp; seq breaks the tie so replay preserves enqueue order. Rows
  // from before the seq field exist without one and sort as 0.
  it('orders by createdAt, breaking same-millisecond ties by seq', () => {
    const commands = [
      cmd({ id: 'third', createdAt: 5, seq: 3 }),
      cmd({ id: 'second', createdAt: 5, seq: 1 }),
      cmd({ id: 'first', createdAt: 3 }),
    ]

    const sorted = [...commands].sort(byQueueOrder)

    expect(sorted.map((c) => c.id)).toEqual(['first', 'second', 'third'])
  })
})
