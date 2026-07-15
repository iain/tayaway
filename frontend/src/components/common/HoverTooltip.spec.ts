import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { mount, VueWrapper } from '@vue/test-utils'
import HoverTooltip, { SHOW_DELAY_MS } from './HoverTooltip.vue'

let wrapper: VueWrapper | null = null
let anchor: HTMLElement | null = null

// The panel teleports to <body>, so query the document, not the wrapper.
function panel(): HTMLElement | null {
  return document.body.querySelector('[role="tooltip"]')
}

function stubHoverCapable(matches: boolean) {
  vi.stubGlobal(
    'matchMedia',
    vi.fn().mockImplementation((query: string) => ({
      matches: query === '(hover: hover)' ? matches : false,
      media: query,
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    }))
  )
}

function mountTooltip() {
  anchor = document.createElement('div')
  document.body.appendChild(anchor)
  wrapper = mount(HoverTooltip, {
    props: { anchorEl: anchor },
    slots: { default: '<p>Added by Alice</p>' },
    attachTo: document.body,
  })
  return wrapper
}

async function hoverAndWait(w: VueWrapper, ms: number = SHOW_DELAY_MS) {
  anchor!.dispatchEvent(new MouseEvent('mouseenter'))
  vi.advanceTimersByTime(ms)
  await w.vm.$nextTick()
}

beforeEach(() => {
  vi.useFakeTimers()
  stubHoverCapable(true)
})

afterEach(() => {
  wrapper?.unmount()
  anchor?.remove()
  wrapper = null
  anchor = null
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

describe('HoverTooltip', () => {
  it('stays hidden before the hover delay elapses', async () => {
    const w = mountTooltip()
    await hoverAndWait(w, SHOW_DELAY_MS - 1)
    expect(panel()).toBeNull()
  })

  it('shows the slot content after hovering for the delay', async () => {
    const w = mountTooltip()
    await hoverAndWait(w)
    expect(panel()).not.toBeNull()
    expect(panel()!.textContent).toContain('Added by Alice')
  })

  it('does not show when the mouse leaves before the delay', async () => {
    const w = mountTooltip()
    anchor!.dispatchEvent(new MouseEvent('mouseenter'))
    vi.advanceTimersByTime(SHOW_DELAY_MS - 1)
    anchor!.dispatchEvent(new MouseEvent('mouseleave'))
    vi.advanceTimersByTime(SHOW_DELAY_MS)
    await w.vm.$nextTick()
    expect(panel()).toBeNull()
  })

  it('hides on mouseleave', async () => {
    const w = mountTooltip()
    await hoverAndWait(w)
    anchor!.dispatchEvent(new MouseEvent('mouseleave'))
    await w.vm.$nextTick()
    expect(panel()).toBeNull()
  })

  it('hides when the page scrolls', async () => {
    const w = mountTooltip()
    await hoverAndWait(w)
    window.dispatchEvent(new Event('scroll'))
    await w.vm.$nextTick()
    expect(panel()).toBeNull()
  })

  it('never takes focus and is invisible to pointer events and screen readers', async () => {
    const focused = document.createElement('button')
    document.body.appendChild(focused)
    focused.focus()

    const w = mountTooltip()
    await hoverAndWait(w)

    expect(document.activeElement).toBe(focused)
    expect(panel()!.className).toContain('pointer-events-none')
    expect(panel()!.getAttribute('aria-hidden')).toBe('true')
    focused.remove()
  })

  it('does nothing on devices without hover', async () => {
    stubHoverCapable(false)
    const w = mountTooltip()
    await hoverAndWait(w)
    expect(panel()).toBeNull()
  })
})
