import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createApp } from 'vue'
import { useNow } from './useNow'

// Run the composable inside a real Vue app so onUnmounted works correctly.
function mountUseNow() {
  let result: ReturnType<typeof useNow>
  const app = createApp({
    setup() {
      result = useNow()
      return () => null
    },
  })
  const el = document.createElement('div')
  app.mount(el)
  return {
    get now() {
      return result.now
    },
    unmount: () => app.unmount(),
  }
}

/** Return the number of ms until the next local midnight from the given date. */
function msUntilLocalMidnight(d: Date): number {
  return (
    new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime() -
    d.getTime()
  )
}

describe('useNow', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('initialises now to the current date', () => {
    const fixedDate = new Date(2026, 2, 22, 10, 0, 0) // 2026-03-22 10:00 local
    vi.setSystemTime(fixedDate)

    const { now, unmount } = mountUseNow()

    expect(now.value.getTime()).toBe(fixedDate.getTime())
    unmount()
  })

  it('updates now when local midnight arrives', () => {
    // 1 second before local midnight on 2026-03-22
    const startDate = new Date(2026, 2, 22, 23, 59, 59)
    vi.setSystemTime(startDate)

    const { now, unmount } = mountUseNow()
    expect(now.value.getDate()).toBe(22)

    // Advance past local midnight
    vi.advanceTimersByTime(msUntilLocalMidnight(startDate) + 1)

    expect(now.value.getDate()).toBe(23)
    unmount()
  })

  it('continues updating on subsequent midnights', () => {
    const startDate = new Date(2026, 2, 22, 23, 59, 59)
    vi.setSystemTime(startDate)

    const { now, unmount } = mountUseNow()

    // First midnight: advance to 00:00:01 on March 23
    vi.advanceTimersByTime(msUntilLocalMidnight(startDate) + 1)
    expect(now.value.getDate()).toBe(23)

    // Second midnight: advance another full day
    vi.advanceTimersByTime(24 * 60 * 60 * 1_000)
    expect(now.value.getDate()).toBe(24)

    unmount()
  })

  it('does not update before local midnight', () => {
    const startDate = new Date(2026, 2, 22, 10, 0, 0)
    vi.setSystemTime(startDate)

    const { now, unmount } = mountUseNow()
    const initialDate = now.value.getDate()

    // Advance to just 1 second before midnight
    vi.advanceTimersByTime(msUntilLocalMidnight(startDate) - 1_000)

    expect(now.value.getDate()).toBe(initialDate)
    unmount()
  })

  it('clears the timer on unmount', () => {
    vi.setSystemTime(new Date(2026, 2, 22, 23, 59, 59))
    const clearSpy = vi.spyOn(globalThis, 'clearTimeout')

    const { unmount } = mountUseNow()
    unmount()

    expect(clearSpy).toHaveBeenCalled()
    clearSpy.mockRestore()
  })
})
