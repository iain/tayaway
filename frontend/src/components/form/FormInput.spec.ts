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

    it('applies a danger outline to the input that persists on focus', () => {
      const wrapper = mount(FormInput, {
        props: { ...baseProps, error: 'Required' },
      })
      const cls = wrapper.get('input').classes().join(' ')
      expect(cls).toContain('outline-state-danger-outline')
      expect(cls).toContain('focus:outline-state-danger-outline')
      expect(cls).not.toContain('outline-gray-300')
      expect(cls).not.toContain('focus:outline-focus')
    })

    it('still wires the error state when a prefix is shown', () => {
      const wrapper = mount(FormInput, {
        props: { ...baseProps, prefix: 'tayaway.com/', error: 'Bad URL' },
      })
      const wrapperDiv = wrapper.get('input').element
        .parentElement as HTMLElement
      expect(wrapperDiv.className).toContain('outline-state-danger-outline')
      expect(wrapperDiv.className).toContain(
        'focus-within:outline-state-danger-outline'
      )
      expect(wrapper.get('input').attributes('aria-invalid')).toBe('true')
    })
  })
})
