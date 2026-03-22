import { ref, onUnmounted } from 'vue'

/**
 * Returns a reactive `now` ref that updates at midnight (local time).
 *
 * The timer fires once at the next midnight, then reschedules itself so
 * date-dependent computeds (e.g. event categorisation) stay accurate for
 * apps left open overnight without requiring a page refresh.
 */
export function useNow() {
  const now = ref(new Date())

  let timer: ReturnType<typeof setTimeout>

  function scheduleNextMidnight() {
    const n = new Date()
    const msUntilMidnight =
      new Date(n.getFullYear(), n.getMonth(), n.getDate() + 1).getTime() -
      n.getTime()

    timer = setTimeout(() => {
      now.value = new Date()
      scheduleNextMidnight()
    }, msUntilMidnight)
  }

  scheduleNextMidnight()

  onUnmounted(() => clearTimeout(timer))

  return { now }
}
