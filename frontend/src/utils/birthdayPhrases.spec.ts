import { describe, it, expect } from 'vitest'
import { BIRTHDAY_LOADING_PHRASES, pickBirthdayPhrase } from './birthdayPhrases'

describe('pickBirthdayPhrase', () => {
  it('always returns one of the known phrases', () => {
    for (let i = 0; i < 200; i++) {
      expect(BIRTHDAY_LOADING_PHRASES).toContain(
        pickBirthdayPhrase(`seed-${i}`)
      )
    }
  })

  it('is deterministic for a given seed', () => {
    expect(pickBirthdayPhrase('member-1:4')).toBe(
      pickBirthdayPhrase('member-1:4')
    )
  })

  it('varies across seeds so different cards and buckets diverge', () => {
    const sampled = new Set(
      Array.from({ length: 50 }, (_, i) => pickBirthdayPhrase(`member:${i}`))
    )
    // A single fixed phrase would collapse to a set of size 1; we expect the
    // hash to spread across most of the list.
    expect(sampled.size).toBeGreaterThan(BIRTHDAY_LOADING_PHRASES.length / 2)
  })
})
