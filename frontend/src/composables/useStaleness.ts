// Thresholds for cache staleness tiers (in milliseconds)
export const STALENESS_THRESHOLDS = {
  // Under 5 minutes: data is fresh, no indicator needed
  STALE_MS: 5 * 60 * 1000,
  // 5 minutes – 24 hours: subtle "Last synced X ago" indicator
  WARNING_MS: 24 * 60 * 60 * 1000,
  // 1 – 7 days: amber banner warning
  EXPIRED_MS: 7 * 24 * 60 * 60 * 1000,
  // Over 7 days: cache is expired, clear it and do a full sync
} as const

export type StalenessLevel = 'fresh' | 'stale' | 'warning' | 'expired'

/**
 * Compute the staleness level of cached data given its syncedAt timestamp.
 *
 * - fresh:   < 5 minutes old — show nothing
 * - stale:   5 min – 24 hours old — show "Last synced X ago" in connection badge
 * - warning: 1 – 7 days old — show amber banner
 * - expired: > 7 days old — clear cache, do full sync, show welcome-back state
 */
export function getStaleness(syncedAt: string): StalenessLevel {
  const ageMs = Date.now() - new Date(syncedAt).getTime()

  if (ageMs < STALENESS_THRESHOLDS.STALE_MS) return 'fresh'
  if (ageMs < STALENESS_THRESHOLDS.WARNING_MS) return 'stale'
  if (ageMs < STALENESS_THRESHOLDS.EXPIRED_MS) return 'warning'
  return 'expired'
}

/**
 * Return the number of full days since syncedAt (clamped to 0).
 * Used for the warning banner copy: "offline for X days".
 */
export function staleDays(syncedAt: string): number {
  const ageMs = Date.now() - new Date(syncedAt).getTime()
  return Math.max(0, Math.floor(ageMs / 86400000))
}
