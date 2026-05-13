import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import LedgerAmount from './LedgerAmount.vue'

describe('LedgerAmount', () => {
  function render(props: {
    amount: number
    direction?: 'in' | 'out'
    locale?: string
  }) {
    return mount(LedgerAmount, { props })
  }

  describe('basic formatting', () => {
    it('renders euro amounts with two decimal places', () => {
      const wrapper = render({ amount: 42.5, locale: 'en-US' })
      expect(wrapper.text()).toBe('€42.50')
    })

    it('renders a thousands separator for large amounts', () => {
      const wrapper = render({ amount: 1234.56, locale: 'en-US' })
      expect(wrapper.text()).toBe('€1,234.56')
    })

    it('formats zero with two decimals', () => {
      const wrapper = render({ amount: 0, locale: 'en-US' })
      expect(wrapper.text()).toBe('€0.00')
    })
  })

  describe('locale variations', () => {
    it('uses comma decimals and dot thousands for nl-NL', () => {
      const wrapper = render({ amount: 1234.56, locale: 'nl-NL' })
      // nl-NL formats as "€ 1.234,56" — exact spacing depends on ICU, so we
      // assert the digits, separator, and decimal style rather than the
      // full string.
      const text = wrapper.text()
      expect(text).toContain('1.234,56')
      expect(text).toContain('€')
    })

    it('places the currency after the number in fr-FR', () => {
      const wrapper = render({ amount: 42.5, locale: 'fr-FR' })
      const text = wrapper.text()
      // fr-FR puts the symbol after the number with a space: "42,50 €"
      expect(text.indexOf('€')).toBeGreaterThan(text.indexOf('42'))
      expect(text).toContain('42,50')
    })
  })

  describe('direction sign', () => {
    it('shows a leading + for inflow', () => {
      const wrapper = render({ amount: 12, direction: 'in', locale: 'en-US' })
      expect(wrapper.text().startsWith('+')).toBe(true)
    })

    it('shows a true Unicode minus for outflow', () => {
      const wrapper = render({ amount: 12, direction: 'out', locale: 'en-US' })
      expect(wrapper.text()).toContain('−') // U+2212
      expect(wrapper.text()).not.toContain('-') // ASCII hyphen
    })

    it('colours the inflow sign with the inflow ink token', () => {
      const wrapper = render({ amount: 12, direction: 'in', locale: 'en-US' })
      const plus = wrapper.findAll('span').find((s) => s.text() === '+')
      expect(plus?.classes()).toContain('text-btn-inflow-ink')
    })

    it('colours the outflow sign with the outflow ink token', () => {
      const wrapper = render({ amount: 12, direction: 'out', locale: 'en-US' })
      const minus = wrapper.findAll('span').find((s) => s.text() === '−')
      expect(minus?.classes()).toContain('text-btn-outflow-ink')
    })
  })

  describe('typography', () => {
    it('wraps the whole amount in tabular-nums for column alignment', () => {
      const wrapper = render({ amount: 42.5, locale: 'en-US' })
      expect(wrapper.classes()).toContain('tabular-nums')
    })

    it('renders the currency symbol in ink-faint', () => {
      const wrapper = render({ amount: 42.5, locale: 'en-US' })
      const currency = wrapper.findAll('span').find((s) => s.text() === '€')
      expect(currency?.classes()).toContain('text-ink-faint')
    })
  })
})
