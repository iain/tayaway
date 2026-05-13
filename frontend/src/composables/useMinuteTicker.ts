import { ref, onUnmounted } from 'vue'

// Module-level reactive clock that ticks once a minute. The interval is
// shared across all consumers via ref counting so 50 `<TimeAnchor>` instances
// share one `setInterval`, and the timer stops when nothing's listening.
const now = ref(Date.now())
let intervalId: ReturnType<typeof setInterval> | null = null
let refCount = 0

function start(): void {
  if (refCount === 0) {
    // Reset to the current clock at every cold start so the first consumer
    // after a quiet period (or a test that just stubbed the clock) doesn't
    // read a stale `now` left over from a previous tick.
    now.value = Date.now()
    intervalId = setInterval(() => {
      now.value = Date.now()
    }, 60_000)
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
 * Returns a reactive `now` ref (epoch ms) that advances once a minute.
 * Powers the staleness indicators in the top nav and every `<TimeAnchor>` —
 * they all agree on what "now" means so two relative timestamps next to
 * each other never drift apart.
 */
export function useMinuteTicker(): { now: typeof now } {
  start()
  onUnmounted(stop)
  return { now }
}
