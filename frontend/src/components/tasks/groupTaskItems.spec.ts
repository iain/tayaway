import { describe, it, expect } from 'vitest'
import {
  groupTaskItems,
  isHistoryItem,
  HISTORY_AFTER_MS,
} from './groupTaskItems'
import { makeTaskItem } from '@/test/factories'

const NOW = Date.parse('2026-07-12T12:00:00.000Z')

function completedAgo(ms: number): string {
  return new Date(NOW - ms).toISOString()
}

describe('isHistoryItem', () => {
  it('is false for incomplete items', () => {
    expect(isHistoryItem(makeTaskItem(), NOW)).toBe(false)
  })

  it('is false for items completed less than an hour ago', () => {
    const item = makeTaskItem({
      completedAt: completedAgo(HISTORY_AFTER_MS - 60_000),
    })
    expect(isHistoryItem(item, NOW)).toBe(false)
  })

  it('is true for items completed an hour or more ago', () => {
    const item = makeTaskItem({ completedAt: completedAgo(HISTORY_AFTER_MS) })
    expect(isHistoryItem(item, NOW)).toBe(true)
  })

  it('becomes true as the clock advances past the threshold', () => {
    const item = makeTaskItem({
      completedAt: completedAgo(HISTORY_AFTER_MS - 60_000),
    })
    expect(isHistoryItem(item, NOW)).toBe(false)
    expect(isHistoryItem(item, NOW + 120_000)).toBe(true)
  })
})

describe('groupTaskItems', () => {
  it('keeps active and recently-completed items in the current group', () => {
    const active = makeTaskItem({ id: 'a', position: 1 })
    const recent = makeTaskItem({
      id: 'b',
      position: 2,
      completedAt: completedAgo(10 * 60_000),
    })
    const { current, history } = groupTaskItems([active, recent], NOW)

    expect(current.map((i) => i.id)).toEqual(['a', 'b'])
    expect(history).toEqual([])
  })

  it('moves items completed over an hour ago into history', () => {
    const active = makeTaskItem({ id: 'a', position: 1 })
    const old = makeTaskItem({
      id: 'b',
      position: 2,
      completedAt: completedAgo(2 * HISTORY_AFTER_MS),
    })
    const { current, history } = groupTaskItems([active, old], NOW)

    expect(current.map((i) => i.id)).toEqual(['a'])
    expect(history.map((i) => i.id)).toEqual(['b'])
  })

  it('sinks recently-completed items below active ones in the current group', () => {
    const recent = makeTaskItem({
      id: 'a',
      position: 1,
      completedAt: completedAgo(60_000),
    })
    const active = makeTaskItem({ id: 'b', position: 2 })
    const { current } = groupTaskItems([recent, active], NOW)

    expect(current.map((i) => i.id)).toEqual(['b', 'a'])
  })

  it('keeps held items pinned in place in the current group', () => {
    const held = makeTaskItem({
      id: 'a',
      position: 1,
      completedAt: completedAgo(60_000),
    })
    const active = makeTaskItem({ id: 'b', position: 2 })
    const { current } = groupTaskItems([held, active], NOW, new Set(['a']))

    expect(current.map((i) => i.id)).toEqual(['a', 'b'])
  })

  it('orders history by completion time, newest first', () => {
    const older = makeTaskItem({
      id: 'a',
      position: 1,
      completedAt: completedAgo(3 * HISTORY_AFTER_MS),
    })
    const newer = makeTaskItem({
      id: 'b',
      position: 2,
      completedAt: completedAgo(HISTORY_AFTER_MS),
    })
    const { history } = groupTaskItems([older, newer], NOW)

    expect(history.map((i) => i.id)).toEqual(['b', 'a'])
  })
})
