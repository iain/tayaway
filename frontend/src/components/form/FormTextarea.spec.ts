import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import FormTextarea from './FormTextarea.vue'

describe('FormTextarea', () => {
  const baseProps = { id: 'notes', label: 'Notes', modelValue: '' }

  it('forwards maxlength to the textarea', () => {
    const wrapper = mount(FormTextarea, {
      props: { ...baseProps, maxlength: 500 },
    })
    expect(wrapper.get('textarea').attributes('maxlength')).toBe('500')
  })

  it('does not set maxlength when none is given', () => {
    const wrapper = mount(FormTextarea, { props: baseProps })
    expect(wrapper.get('textarea').attributes('maxlength')).toBeUndefined()
  })

  describe('character counter', () => {
    it('is hidden unless showCount and a maxlength are both set', () => {
      const withoutCount = mount(FormTextarea, {
        props: { ...baseProps, maxlength: 500 },
      })
      expect(
        withoutCount.find('[data-testid="form-textarea-count"]').exists()
      ).toBe(false)

      const withoutMax = mount(FormTextarea, {
        props: { ...baseProps, showCount: true },
      })
      expect(
        withoutMax.find('[data-testid="form-textarea-count"]').exists()
      ).toBe(false)
    })

    it('renders the current length against the limit', () => {
      const wrapper = mount(FormTextarea, {
        props: {
          ...baseProps,
          modelValue: 'hello',
          maxlength: 500,
          showCount: true,
        },
      })
      expect(wrapper.get('[data-testid="form-textarea-count"]').text()).toBe(
        '5/500'
      )
    })

    it('warns as it nears the limit and turns danger at the limit', () => {
      const near = mount(FormTextarea, {
        props: {
          ...baseProps,
          modelValue: 'a'.repeat(95),
          maxlength: 100,
          showCount: true,
        },
      })
      expect(
        near.get('[data-testid="form-textarea-count"]').classes()
      ).toContain('text-state-warning-ink')

      const full = mount(FormTextarea, {
        props: {
          ...baseProps,
          modelValue: 'a'.repeat(100),
          maxlength: 100,
          showCount: true,
        },
      })
      expect(
        full.get('[data-testid="form-textarea-count"]').classes()
      ).toContain('text-state-danger-ink')
    })
  })
})
