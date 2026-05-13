import { computed, toValue, type ComputedRef, type MaybeRefOrGetter } from 'vue'
import { useMinuteTicker } from './useMinuteTicker'
import { formatRelativeDate } from '@/utils/date'

/**
 * Reactive compact relative-time string ("5m ago", "in 3h", "just now").
 * Re-evaluates every minute via the shared `useMinuteTicker`, so a row's
 * "8m ago" becomes "9m ago" without the consumer wiring up a clock.
 *
 * The default voice is past-tense for past timestamps and future-tense for
 * future ones. Pair with a verb when displaying — see `<TimeAnchor>`.
 */
export function useRelativeTime(
  iso: MaybeRefOrGetter<string | null | undefined>
): ComputedRef<string> {
  const { now } = useMinuteTicker()
  return computed(() => {
    const value = toValue(iso)
    if (!value) return ''
    return formatRelativeDate(value, now.value)
  })
}
