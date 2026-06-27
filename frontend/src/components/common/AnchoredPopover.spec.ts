import { describe, it, expect, afterEach } from 'vitest'
import { mount, VueWrapper } from '@vue/test-utils'
import AnchoredPopover from './AnchoredPopover.vue'

let wrapper: VueWrapper | null = null
let anchor: HTMLButtonElement | null = null

function mountPopover() {
  anchor = document.createElement('button')
  document.body.appendChild(anchor)
  wrapper = mount(AnchoredPopover, {
    props: { anchorEl: anchor, ariaLabel: 'Test popover' },
    slots: { default: '<input data-test="field" />' },
    attachTo: document.body,
  })
  return wrapper
}

afterEach(() => {
  wrapper?.unmount()
  anchor?.remove()
  wrapper = null
  anchor = null
})

describe('AnchoredPopover', () => {
  it('renders a labelled dialog with the e2e-relied-on fixed z-50 classes', () => {
    const root = mountPopover().get('[role="dialog"]')
    expect(root.classes()).toContain('fixed')
    expect(root.classes()).toContain('z-50')
    expect(root.attributes('aria-label')).toBe('Test popover')
  })

  it('moves focus into the popover content on open', () => {
    const w = mountPopover()
    expect(document.activeElement).toBe(w.get('[data-test="field"]').element)
  })

  it('emits close when Escape is pressed', async () => {
    const w = mountPopover()
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
    await w.vm.$nextTick()
    expect(w.emitted('close')).toBeTruthy()
  })

  it('emits close on a mousedown outside the popover', async () => {
    const w = mountPopover()
    anchor!.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }))
    await w.vm.$nextTick()
    expect(w.emitted('close')).toBeTruthy()
  })

  it('does not emit close on a mousedown inside the popover', async () => {
    const w = mountPopover()
    w.get('[data-test="field"]').element.dispatchEvent(
      new MouseEvent('mousedown', { bubbles: true })
    )
    await w.vm.$nextTick()
    expect(w.emitted('close')).toBeFalsy()
  })
})
