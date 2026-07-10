import { describe, it, expect } from 'vitest'
import { shouldSuggestAutofill } from './chores'
import { makeChore } from '@/test/factories'

describe('shouldSuggestAutofill', () => {
  it('suggests while the roster is less than half full', () => {
    // 2 chores x 3 days x 1 person = 6 seats; 2 assigned is under half
    const chores = [makeChore(), makeChore({ id: 'chore-2' })]
    expect(shouldSuggestAutofill(chores, 3, 2)).toBe(true)
  })

  it('stops suggesting once the roster reaches half full', () => {
    const chores = [makeChore(), makeChore({ id: 'chore-2' })]
    expect(shouldSuggestAutofill(chores, 3, 3)).toBe(false)
  })

  it('counts multi-person chores by their seats', () => {
    // 1 chore x 2 days x 3 people = 6 seats; 2 assigned is under half
    const chores = [makeChore({ peoplePerDay: 3 })]
    expect(shouldSuggestAutofill(chores, 2, 2)).toBe(true)
  })

  it('never suggests for an empty roster', () => {
    expect(shouldSuggestAutofill([], 3, 0)).toBe(false)
  })
})
