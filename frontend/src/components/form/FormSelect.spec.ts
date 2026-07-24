import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import FormSelect from './FormSelect.vue'

describe('FormSelect', () => {
  const baseProps = {
    id: 'field',
    label: 'Field',
    modelValue: 'a',
    options: [
      { value: 'a', label: 'Alpha' },
      { value: 'b', label: 'Beta' },
    ],
  }

  it('renders each option selectable by default', () => {
    const wrapper = mount(FormSelect, { props: baseProps })
    const options = wrapper.findAll('option')
    expect(options.map((o) => o.text())).toEqual(['Alpha', 'Beta'])
    for (const option of options) {
      expect(option.attributes('disabled')).toBeUndefined()
    }
  })

  it('disables an option marked disabled', () => {
    const wrapper = mount(FormSelect, {
      props: {
        ...baseProps,
        options: [
          { value: 'a', label: 'Alpha' },
          { value: 'b', label: 'Beta', disabled: true },
        ],
      },
    })
    expect(
      wrapper.get('option[value="b"]').attributes('disabled')
    ).toBeDefined()
    expect(
      wrapper.get('option[value="a"]').attributes('disabled')
    ).toBeUndefined()
  })

  it('forwards extra attributes to the select element, not the wrapper', () => {
    const wrapper = mount(FormSelect, {
      props: baseProps,
      attrs: { 'data-testid': 'my-select' },
    })
    expect(wrapper.get('select').attributes('data-testid')).toBe('my-select')
    expect(wrapper.element.getAttribute('data-testid')).toBeNull()
  })

  it('emits the picked value', async () => {
    const wrapper = mount(FormSelect, { props: baseProps })
    await wrapper.get('select').setValue('b')
    expect(wrapper.emitted('update:modelValue')).toEqual([['b']])
  })

  it('shows the label by default and keeps it wired to the select', () => {
    const wrapper = mount(FormSelect, { props: baseProps })
    const label = wrapper.get('label')
    expect(label.classes()).not.toContain('sr-only')
    expect(label.attributes('for')).toBe('field')
  })

  it('keeps the label for assistive tech when hidden', () => {
    const wrapper = mount(FormSelect, {
      props: { ...baseProps, hideLabel: true },
    })
    const label = wrapper.get('label')
    // Still present and associated — just visually removed.
    expect(label.classes()).toContain('sr-only')
    expect(label.attributes('for')).toBe('field')
    expect(label.text()).toBe('Field')
  })
})
