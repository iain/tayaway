import { describe, it, expect } from 'vitest'
import { sortTaskItems } from './sortTaskItems'
import type { PoolTaskItem } from '@/types/pool'

function mkItem(overrides: Partial<PoolTaskItem>): PoolTaskItem {
  return {
    id: 'x',
    objectType: 'taskItem',
    taskListId: 'list-1',
    userId: null,
    content: 'x',
    completedAt: null,
    position: 0,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

const DONE = '2026-01-02T00:00:00.000Z'

describe('sortTaskItems', () => {
  it('orders incomplete items by position', () => {
    const items = [
      mkItem({ id: 'b', position: 2 }),
      mkItem({ id: 'a', position: 1 }),
      mkItem({ id: 'c', position: 3 }),
    ]
    expect(sortTaskItems(items).map((i) => i.id)).toEqual(['a', 'b', 'c'])
  })

  it('sinks completed items below incomplete ones', () => {
    const items = [
      mkItem({ id: 'apples', position: 1, completedAt: null }),
      mkItem({ id: 'milk', position: 2, completedAt: DONE }),
      mkItem({ id: 'bread', position: 3, completedAt: null }),
    ]
    // Completed 'milk' drops to the bottom to declutter the active list.
    expect(sortTaskItems(items).map((i) => i.id)).toEqual([
      'apples',
      'bread',
      'milk',
    ])
  })

  it('orders multiple completed items among themselves by position', () => {
    const items = [
      mkItem({ id: 'b-done', position: 2, completedAt: DONE }),
      mkItem({ id: 'a-todo', position: 1, completedAt: null }),
      mkItem({ id: 'c-done', position: 3, completedAt: DONE }),
    ]
    expect(sortTaskItems(items).map((i) => i.id)).toEqual([
      'a-todo',
      'b-done',
      'c-done',
    ])
  })

  it('keeps a held completed item in place, not sunk (the ~1s hold after a tap)', () => {
    const items = [
      mkItem({ id: 'apples', position: 1, completedAt: null }),
      mkItem({ id: 'milk', position: 2, completedAt: DONE }),
      mkItem({ id: 'bread', position: 3, completedAt: null }),
    ]
    // 'milk' was just tapped and is held — it stays between apples and bread
    // until the hold expires, so it doesn't jump out from under the finger.
    expect(sortTaskItems(items, new Set(['milk'])).map((i) => i.id)).toEqual([
      'apples',
      'milk',
      'bread',
    ])
  })

  it('breaks position ties by createdAt so all clients agree', () => {
    // Two clients adding concurrently can both get max_position + 1.
    const items = [
      mkItem({
        id: 'later',
        position: 2,
        createdAt: '2026-01-01T00:00:05.000Z',
      }),
      mkItem({
        id: 'earlier',
        position: 2,
        createdAt: '2026-01-01T00:00:01.000Z',
      }),
      mkItem({ id: 'first', position: 1 }),
    ]
    expect(sortTaskItems(items).map((i) => i.id)).toEqual([
      'first',
      'earlier',
      'later',
    ])
  })

  it('breaks position and createdAt ties by content, then id', () => {
    const items = [
      mkItem({ id: 'aaa', position: 1, content: 'bananas' }),
      mkItem({ id: 'zzz', position: 1, content: 'apples' }),
      mkItem({ id: 'bbb', position: 1, content: 'bananas' }),
    ]
    // 'apples' sorts first despite the highest id; equal contents fall
    // back to id.
    expect(sortTaskItems(items).map((i) => i.id)).toEqual(['zzz', 'aaa', 'bbb'])
  })

  it('produces the same order regardless of input order', () => {
    // Pool insertion order differs per client; the result must not.
    const items = [
      mkItem({ id: 'bbb', position: 1 }),
      mkItem({ id: 'aaa', position: 1 }),
      mkItem({ id: 'ccc', position: 1, createdAt: '2025-12-31T00:00:00.000Z' }),
    ]
    const forward = sortTaskItems(items).map((i) => i.id)
    const reversed = sortTaskItems([...items].reverse()).map((i) => i.id)
    expect(forward).toEqual(['ccc', 'aaa', 'bbb'])
    expect(reversed).toEqual(forward)
  })

  it('does not mutate the input array', () => {
    const items = [
      mkItem({ id: 'b', position: 2 }),
      mkItem({ id: 'a', position: 1 }),
    ]
    sortTaskItems(items)
    expect(items.map((i) => i.id)).toEqual(['b', 'a'])
  })
})
