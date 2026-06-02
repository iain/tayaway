import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import FormInput from './FormInput.vue'

describe('FormInput', () => {
  const baseProps = { id: 'field', label: 'Field', modelValue: '' }

  describe('without error', () => {
    it('does not render an error message', () => {
      const wrapper = mount(FormInput, { props: baseProps })
      expect(wrapper.find('p').exists()).toBe(false)
    })

    it('does not mark the input as invalid', () => {
      const wrapper = mount(FormInput, { props: baseProps })
      const input = wrapper.get('input')
      expect(input.attributes('aria-invalid')).toBeUndefined()
      expect(input.attributes('aria-describedby')).toBeUndefined()
    })

    it('renders an outset focus outline matching the system-wide focus vocabulary', () => {
      const wrapper = mount(FormInput, { props: baseProps })
      const cls = wrapper.get('input').classes().join(' ')
      expect(cls).toContain('focus:outline-2')
      expect(cls).toContain('focus:outline-offset-2')
      expect(cls).toContain('focus:outline-focus')
      expect(cls).not.toContain('focus:-outline-offset-2')
    })
  })

  describe('with error', () => {
    it('renders the error message below the input', () => {
      const wrapper = mount(FormInput, {
        props: { ...baseProps, error: 'Required' },
      })
      const message = wrapper.get('p')
      expect(message.text()).toBe('Required')
    })

    it('marks the input as invalid and points aria-describedby at the message', () => {
      const wrapper = mount(FormInput, {
        props: { ...baseProps, error: 'Required' },
      })
      const input = wrapper.get('input')
      expect(input.attributes('aria-invalid')).toBe('true')
      expect(input.attributes('aria-describedby')).toBe('field-error')
      expect(wrapper.get('p').attributes('id')).toBe('field-error')
    })

    it('signals error through fill, outline, and icon — but leaves focus orthogonal', () => {
      const wrapper = mount(FormInput, {
        props: { ...baseProps, error: 'Required' },
      })
      const cls = wrapper.get('input').classes().join(' ')

      expect(cls).toContain('bg-state-danger-fill')
      expect(cls).toContain('outline-1')
      expect(cls).toContain('outline-state-danger-outline')
      expect(cls).not.toContain('outline-line')
      expect(cls).not.toContain('bg-surface-sunken')

      // Focus stays the system-wide rose ring — error signal is fill + icon,
      // not a competing focus-color override.
      expect(cls).toContain('focus:outline-focus')
      expect(cls).not.toContain('focus:outline-state-danger-outline')

      expect(
        wrapper.find('[data-testid="form-input-error-icon"]').exists()
      ).toBe(true)
    })

    it('still wires the error state when a prefix is shown', () => {
      const wrapper = mount(FormInput, {
        props: { ...baseProps, prefix: 'tayaway.com/', error: 'Bad URL' },
      })
      const shell = wrapper.get('input').element.parentElement as HTMLElement
      expect(shell.className).toContain('bg-state-danger-fill')
      expect(shell.className).toContain('outline-state-danger-outline')
      expect(shell.className).not.toContain(
        'focus-within:outline-state-danger-outline'
      )
      expect(wrapper.get('input').attributes('aria-invalid')).toBe('true')
      expect(
        wrapper.find('[data-testid="form-input-error-icon"]').exists()
      ).toBe(true)
    })
  })

  describe('icon visibility', () => {
    it('does not render the error icon for healthy fields', () => {
      const wrapper = mount(FormInput, { props: baseProps })
      expect(
        wrapper.find('[data-testid="form-input-error-icon"]').exists()
      ).toBe(false)
    })
  })
})
