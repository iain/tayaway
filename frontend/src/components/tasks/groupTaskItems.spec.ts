import { describe, it, expect } from 'vitest'
import {
  groupTaskItems,
  isHistoryItem,
  HISTORY_AFTER_MS,
} from './groupTaskItems'
import type { PoolTaskItem } from '@/types/pool'

const NOW = Date.parse('2026-07-12T12:00:00.000Z')

function mkItem(overrides: Partial<PoolTaskItem> = {}): PoolTaskItem {
  return {
    id: 'item-1',
    objectType: 'taskItem',
    taskListId: 'list-1',
    userId: 'user-1',
    content: 'Buy milk',
    completedAt: null,
    position: 1,
    createdAt: '2026-07-12T08:00:00.000Z',
    updatedAt: '2026-07-12T08:00:00.000Z',
    ...overrides,
  }
}

function completedAgo(ms: number): string {
  return new Date(NOW - ms).toISOString()
}

const NONE: ReadonlySet<string> = new Set()

describe('isHistoryItem', () => {
  it('is false for incomplete items', () => {
    expect(isHistoryItem(mkItem(), NOW)).toBe(false)
  })

  it('is false for items completed less than an hour ago', () => {
    const item = mkItem({
      completedAt: completedAgo(HISTORY_AFTER_MS - 60_000),
    })
    expect(isHistoryItem(item, NOW)).toBe(false)
  })

  it('is true for items completed an hour or more ago', () => {
    const item = mkItem({ completedAt: completedAgo(HISTORY_AFTER_MS) })
    expect(isHistoryItem(item, NOW)).toBe(true)
  })

  it('becomes true as the clock advances past the threshold', () => {
    const item = mkItem({
      completedAt: completedAgo(HISTORY_AFTER_MS - 60_000),
    })
    expect(isHistoryItem(item, NOW)).toBe(false)
    expect(isHistoryItem(item, NOW + 120_000)).toBe(true)
  })
})

describe('groupTaskItems', () => {
  it('keeps active and recently-completed items in the current group', () => {
    const active = mkItem({ id: 'a', position: 1 })
    const recent = mkItem({
      id: 'b',
      position: 2,
      completedAt: completedAgo(10 * 60_000),
    })
    const { current, history } = groupTaskItems([active, recent], NONE, NOW)

    expect(current.map((i) => i.id)).toEqual(['a', 'b'])
    expect(history).toEqual([])
  })

  it('moves items completed over an hour ago into history', () => {
    const active = mkItem({ id: 'a', position: 1 })
    const old = mkItem({
      id: 'b',
      position: 2,
      completedAt: completedAgo(2 * HISTORY_AFTER_MS),
    })
    const { current, history } = groupTaskItems([active, old], NONE, NOW)

    expect(current.map((i) => i.id)).toEqual(['a'])
    expect(history.map((i) => i.id)).toEqual(['b'])
  })

  it('sinks recently-completed items below active ones in the current group', () => {
    const recent = mkItem({
      id: 'a',
      position: 1,
      completedAt: completedAgo(60_000),
    })
    const active = mkItem({ id: 'b', position: 2 })
    const { current } = groupTaskItems([recent, active], NONE, NOW)

    expect(current.map((i) => i.id)).toEqual(['b', 'a'])
  })

  it('orders history by completion time, newest first', () => {
    const older = mkItem({
      id: 'a',
      position: 1,
      completedAt: completedAgo(3 * HISTORY_AFTER_MS),
    })
    const newer = mkItem({
      id: 'b',
      position: 2,
      completedAt: completedAgo(HISTORY_AFTER_MS),
    })
    const { history } = groupTaskItems([older, newer], NONE, NOW)

    expect(history.map((i) => i.id)).toEqual(['b', 'a'])
  })

  it('never sends a held item to history', () => {
    // A hold means the user toggled the item moments ago; even with a skewed
    // timestamp it must stay pinned in the current group.
    const held = mkItem({
      id: 'a',
      completedAt: completedAgo(2 * HISTORY_AFTER_MS),
    })
    const { current, history } = groupTaskItems([held], new Set(['a']), NOW)

    expect(current.map((i) => i.id)).toEqual(['a'])
    expect(history).toEqual([])
  })
})
