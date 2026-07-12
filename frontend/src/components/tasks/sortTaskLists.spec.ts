import { describe, it, expect } from 'vitest'
import { sortTaskLists } from './sortTaskLists'
import type { PoolTaskList } from '@/types/pool'

function mkList(overrides: Partial<PoolTaskList>): PoolTaskList {
  return {
    id: 'x',
    objectType: 'taskList',
    workspaceId: 'ws-1',
    userId: null,
    name: 'x',
    position: 0,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

describe('sortTaskLists', () => {
  it('orders lists by position', () => {
    const lists = [
      mkList({ id: 'b', position: 2 }),
      mkList({ id: 'a', position: 1 }),
      mkList({ id: 'c', position: 3 }),
    ]
    expect(sortTaskLists(lists).map((l) => l.id)).toEqual(['a', 'b', 'c'])
  })

  it('breaks position ties by createdAt, then name, then id', () => {
    const lists = [
      mkList({ id: 'bbb', position: 1 }),
      mkList({ id: 'aaa', position: 1 }),
      mkList({ id: 'zzz', position: 1, name: 'aardvarks' }),
      mkList({
        id: 'newer',
        position: 1,
        createdAt: '2026-01-02T00:00:00.000Z',
      }),
    ]
    // Among the three created at the same time, 'aardvarks' sorts before
    // the two named 'x' (which fall back to id); the later creation sorts
    // last regardless of name.
    expect(sortTaskLists(lists).map((l) => l.id)).toEqual([
      'zzz',
      'aaa',
      'bbb',
      'newer',
    ])
  })

  it('produces the same order regardless of input order', () => {
    const lists = [
      mkList({ id: 'bbb', position: 1 }),
      mkList({ id: 'aaa', position: 1 }),
    ]
    const forward = sortTaskLists(lists).map((l) => l.id)
    const reversed = sortTaskLists([...lists].reverse()).map((l) => l.id)
    expect(reversed).toEqual(forward)
  })

  it('does not mutate the input array', () => {
    const lists = [
      mkList({ id: 'b', position: 2 }),
      mkList({ id: 'a', position: 1 }),
    ]
    sortTaskLists(lists)
    expect(lists.map((l) => l.id)).toEqual(['b', 'a'])
  })
})
