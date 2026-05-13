import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { defineComponent, h, ref } from 'vue'
import { mount, type VueWrapper } from '@vue/test-utils'
import { useRelativeTime } from './useRelativeTime'

describe('useRelativeTime', () => {
  // The minute ticker behind `useRelativeTime` is module-level; if a test
  // leaves a host mounted, the next test inherits its `setInterval` handle
  // from the previous (already-disposed) fake-timer system. Track mounts
  // and unmount in afterEach to keep tests isolated.
  const mounts: VueWrapper[] = []
  function track<T extends VueWrapper>(wrapper: T): T {
    mounts.push(wrapper)
    return wrapper
  }

  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-05-13T12:00:00Z'))
  })

  afterEach(() => {
    while (mounts.length) mounts.pop()?.unmount()
    vi.useRealTimers()
  })

  function host(getter: () => string) {
    return defineComponent({
      setup() {
        return { relative: useRelativeTime(getter) }
      },
      render() {
        return h('span', this.relative)
      },
    })
  }

  it('returns the compact relative-time string for a past timestamp', () => {
    const wrapper = track(mount(host(() => '2026-05-13T09:00:00Z')))
    expect(wrapper.text()).toBe('3h ago')
  })

  it('returns the compact "in" form for a future timestamp', () => {
    const wrapper = track(mount(host(() => '2026-05-13T14:00:00Z')))
    expect(wrapper.text()).toBe('in 2h')
  })

  it('updates as the minute ticker advances', async () => {
    const wrapper = track(mount(host(() => '2026-05-13T11:50:00Z')))
    expect(wrapper.text()).toBe('10m ago')

    vi.advanceTimersByTime(60_000)
    await wrapper.vm.$nextTick()

    expect(wrapper.text()).toBe('11m ago')
  })

  it('reacts when the input ref changes', async () => {
    const iso = ref('2026-05-13T09:00:00Z')
    const wrapper = track(mount(host(() => iso.value)))
    expect(wrapper.text()).toBe('3h ago')

    iso.value = '2026-05-12T12:00:00Z'
    await wrapper.vm.$nextTick()

    expect(wrapper.text()).toBe('1d ago')
  })

  it('renders an empty string when the timestamp is missing', () => {
    const wrapper = track(mount(host(() => '')))
    expect(wrapper.text()).toBe('')
  })
})
