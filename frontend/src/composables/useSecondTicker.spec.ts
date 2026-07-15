import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { defineComponent, h } from 'vue'
import { mount } from '@vue/test-utils'
import { useSecondTicker } from './useSecondTicker'

// The ticker exposes a module-level ref, so each mount/unmount cycle changes
// the shared interval reference count. Tests use fake timers to drive the
// clock forward by exactly a second and assert the ref updated.
describe('useSecondTicker', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  function makeHost() {
    return defineComponent({
      setup() {
        const { now } = useSecondTicker()
        return { now }
      },
      render() {
        return h('span', String(this.now))
      },
    })
  }

  it('advances the now ref after each second', async () => {
    const host = mount(makeHost())
    const initial = Number(host.text())

    vi.advanceTimersByTime(1_000)
    await host.vm.$nextTick()

    const after = Number(host.text())
    expect(after).toBeGreaterThan(initial)
    expect(after - initial).toBeGreaterThanOrEqual(1_000)

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

  it('stops the timer once the last consumer unmounts', async () => {
    const clearIntervalSpy = vi.spyOn(globalThis, 'clearInterval')

    const a = mount(makeHost())
    const b = mount(makeHost())

    a.unmount()
    expect(clearIntervalSpy).not.toHaveBeenCalled()

    b.unmount()
    expect(clearIntervalSpy).toHaveBeenCalledTimes(1)
  })
})
