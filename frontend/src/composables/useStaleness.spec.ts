import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest'
import { getStaleness, staleDays, STALENESS_THRESHOLDS } from './useStaleness'

const NOW = new Date('2026-03-22T12:00:00Z').getTime()

function syncedAtMsAgo(ms: number): string {
  return new Date(NOW - ms).toISOString()
}

describe('getStaleness', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(NOW)
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('returns fresh for timestamps under 5 minutes old', () => {
    expect(getStaleness(syncedAtMsAgo(0))).toBe('fresh')
    expect(getStaleness(syncedAtMsAgo(60_000))).toBe('fresh') // 1 minute
    expect(getStaleness(syncedAtMsAgo(STALENESS_THRESHOLDS.STALE_MS - 1))).toBe(
      'fresh'
    )
  })

  it('returns stale for timestamps between 5 minutes and 24 hours old', () => {
    expect(getStaleness(syncedAtMsAgo(STALENESS_THRESHOLDS.STALE_MS))).toBe(
      'stale'
    )
    expect(getStaleness(syncedAtMsAgo(30 * 60_000))).toBe('stale') // 30 minutes
    expect(
      getStaleness(syncedAtMsAgo(STALENESS_THRESHOLDS.WARNING_MS - 1))
    ).toBe('stale')
  })

  it('returns warning for timestamps between 1 and 7 days old', () => {
    expect(getStaleness(syncedAtMsAgo(STALENESS_THRESHOLDS.WARNING_MS))).toBe(
      'warning'
    )
    expect(getStaleness(syncedAtMsAgo(3 * 24 * 3600_000))).toBe('warning') // 3 days
    expect(
      getStaleness(syncedAtMsAgo(STALENESS_THRESHOLDS.EXPIRED_MS - 1))
    ).toBe('warning')
  })

  it('returns expired for timestamps older than 7 days', () => {
    expect(getStaleness(syncedAtMsAgo(STALENESS_THRESHOLDS.EXPIRED_MS))).toBe(
      'expired'
    )
    expect(getStaleness(syncedAtMsAgo(30 * 24 * 3600_000))).toBe('expired') // 30 days
  })
})

describe('staleDays', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(NOW)
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('returns 0 for timestamps less than 1 day old', () => {
    expect(staleDays(syncedAtMsAgo(0))).toBe(0)
    expect(staleDays(syncedAtMsAgo(23 * 3600_000))).toBe(0)
  })

  it('returns the number of full days elapsed', () => {
    expect(staleDays(syncedAtMsAgo(1 * 24 * 3600_000))).toBe(1)
    expect(staleDays(syncedAtMsAgo(3 * 24 * 3600_000))).toBe(3)
    expect(staleDays(syncedAtMsAgo(7 * 24 * 3600_000))).toBe(7)
  })

  it('returns 0 for future timestamps (clamps negative values)', () => {
    expect(staleDays(syncedAtMsAgo(-60_000))).toBe(0)
  })
})
