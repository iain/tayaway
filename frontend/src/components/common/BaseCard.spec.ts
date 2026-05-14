import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import BaseCard from './BaseCard.vue'

describe('BaseCard', () => {
  describe('non-interactive', () => {
    it('renders without tabindex or role by default', () => {
      const wrapper = mount(BaseCard)
      expect(wrapper.attributes('tabindex')).toBeUndefined()
      expect(wrapper.attributes('role')).toBeUndefined()
    })
  })

  describe('interactive', () => {
    it('adds tabindex="0" and role="button" when interactive', () => {
      const wrapper = mount(BaseCard, { props: { interactive: true } })
      expect(wrapper.attributes('tabindex')).toBe('0')
      expect(wrapper.attributes('role')).toBe('button')
    })

    it('triggers a click when Enter key is pressed', async () => {
      const clickHandler = vi.fn()
      const wrapper = mount(BaseCard, {
        props: { interactive: true },
        attrs: { onClick: clickHandler },
      })
      await wrapper.trigger('keydown', { key: 'Enter' })
      expect(clickHandler).toHaveBeenCalledOnce()
    })

    it('triggers a click when Space key is pressed', async () => {
      const clickHandler = vi.fn()
      const wrapper = mount(BaseCard, {
        props: { interactive: true },
        attrs: { onClick: clickHandler },
      })
      await wrapper.trigger('keydown', { key: ' ' })
      expect(clickHandler).toHaveBeenCalledOnce()
    })

    it('does not trigger a click for other keys', async () => {
      const clickHandler = vi.fn()
      const wrapper = mount(BaseCard, {
        props: { interactive: true },
        attrs: { onClick: clickHandler },
      })
      await wrapper.trigger('keydown', { key: 'Tab' })
      expect(clickHandler).not.toHaveBeenCalled()
    })

    it('renders the system-wide focus outline so keyboard users see Tab focus', () => {
      const wrapper = mount(BaseCard, { props: { interactive: true } })
      const cls = wrapper.classes().join(' ')
      expect(cls).toContain('focus-visible:outline-2')
      expect(cls).toContain('focus-visible:outline-offset-2')
      expect(cls).toContain('focus-visible:outline-focus')
    })

    it('omits the focus outline when not interactive', () => {
      const wrapper = mount(BaseCard)
      const cls = wrapper.classes().join(' ')
      expect(cls).not.toContain('focus-visible:outline-focus')
    })
  })
})
