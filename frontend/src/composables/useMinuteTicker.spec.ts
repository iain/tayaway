import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { defineComponent, h } from 'vue'
import { mount } from '@vue/test-utils'
import { useMinuteTicker } from './useMinuteTicker'

// The ticker exposes a module-level ref, so each mount/unmount cycle changes
// the shared interval reference count. Tests use real timers stubbed with vi
// to drive the clock forward by exactly a minute and assert the ref updated.
describe('useMinuteTicker', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  function makeHost() {
    return defineComponent({
      setup() {
        const { now } = useMinuteTicker()
        return { now }
      },
      render() {
        return h('span', String(this.now))
      },
    })
  }

  it('advances the now ref after each minute', async () => {
    const host = mount(makeHost())
    const initial = Number(host.text())

    vi.advanceTimersByTime(60_000)
    await host.vm.$nextTick()

    const after = Number(host.text())
    expect(after).toBeGreaterThan(initial)
    expect(after - initial).toBeGreaterThanOrEqual(60_000)

    host.unmount()
  })

  it('shares a single timer across simultaneous consumers', async () => {
    const setIntervalSpy = vi.spyOn(globalThis, 'setInterval')

    const a = mount(makeHost())
    const b = mount(makeHost())
    const c = mount(makeHost())

    // Three consumers should not provoke three intervals.
    expect(setIntervalSpy).toHaveBeenCalledTimes(1)

    a.unmount()
    b.unmount()
    c.unmount()
  })
})
