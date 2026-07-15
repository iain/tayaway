import { ref, onUnmounted } from 'vue'

// Module-level reactive clock that ticks once a second. Like `useMinuteTicker`
// it shares a single `setInterval` across all consumers via ref counting, so a
// dashboard full of birthday countdowns all tick in lockstep off one timer and
// the interval stops the moment the last card unmounts. Reserve this for the
// rare live-by-the-second surface (the birthday countdown) — anything measured
// in minutes should use `useMinuteTicker` to stay cheap.
const now = ref(Date.now())
let intervalId: ReturnType<typeof setInterval> | null = null
let refCount = 0

function start(): void {
  if (refCount === 0) {
    // Reset to the current clock on cold start so the first consumer after a
    // quiet period (or a test that just stubbed the clock) doesn't read a
    // stale `now` left over from a previous tick.
    now.value = Date.now()
    intervalId = setInterval(() => {
      now.value = Date.now()
    }, 1_000)
  }
  refCount += 1
}

function stop(): void {
  refCount -= 1
  if (refCount === 0 && intervalId !== null) {
    clearInterval(intervalId)
    intervalId = null
  }
}

/**
 * Returns a reactive `now` ref (epoch ms) that advances once a second.
 * Powers the birthday countdown on the dashboard — every countdown card reads
 * the same `now`, so the ticking digits never drift apart between cards.
 */
export function useSecondTicker(): { now: typeof now } {
  start()
  onUnmounted(stop)
  return { now }
}
