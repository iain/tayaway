import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, type VueWrapper } from '@vue/test-utils'
import TimeAnchor from './TimeAnchor.vue'

describe('TimeAnchor', () => {
  // See useRelativeTime.spec.ts for why we track + unmount: the minute
  // ticker is module-level shared state, and a host left mounted across
  // tests would carry a stale setInterval handle from the previous
  // fake-timer system.
  const mounts: VueWrapper[] = []

  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-05-13T12:00:00Z'))
  })

  afterEach(() => {
    while (mounts.length) mounts.pop()?.unmount()
    vi.useRealTimers()
  })

  function render(
    props: { at: string; title?: string },
    slots?: { default?: string }
  ): VueWrapper {
    const wrapper = mount(TimeAnchor, { props, slots })
    mounts.push(wrapper)
    return wrapper
  }

  it('renders the compact relative time inside a <time> element', () => {
    const wrapper = render({ at: '2026-05-13T09:00:00Z' })
    const time = wrapper.get('time')
    expect(time.text()).toBe('3h ago')
    expect(time.attributes('datetime')).toBe('2026-05-13T09:00:00Z')
  })

  it('renders the verb slot before the relative time', () => {
    const wrapper = render(
      { at: '2026-05-13T09:00:00Z' },
      { default: 'Sent' }
    )
    expect(wrapper.text()).toContain('Sent')
    expect(wrapper.text()).toMatch(/Sent\s+3h ago/)
  })

  it('renders just the time when no verb slot is provided', () => {
    const wrapper = render({ at: '2026-05-13T09:00:00Z' })
    expect(wrapper.text().trim()).toBe('3h ago')
  })

  describe('tooltip', () => {
    it('exposes the absolute date+time via a title attribute by default', () => {
      const wrapper = render({ at: '2026-05-13T09:00:00Z' })
      const title = wrapper.attributes('title')
      // formatDateTime renders through ICU + the runtime locale + timezone,
      // so the exact string varies. Assert on what the tooltip must
      // communicate: a month + day + clock time.
      expect(title).toBeTruthy()
      expect(title).toMatch(/May/)
      expect(title).toMatch(/:\d{2}/)
    })

    it('honours an explicit title prop as an override', () => {
      const wrapper = render({
        at: '2026-05-13T09:00:00Z',
        title: 'When it actually happened',
      })
      expect(wrapper.attributes('title')).toBe('When it actually happened')
    })
  })
})
