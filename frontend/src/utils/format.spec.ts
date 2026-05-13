import { describe, expect, it } from 'vitest'
import { formatAmount } from './format'

describe('formatAmount', () => {
  describe('default locale (en-US)', () => {
    it('formats a whole number', () => {
      expect(formatAmount(10)).toBe('€10.00')
    })

    it('formats a value with one decimal place', () => {
      expect(formatAmount(12.5)).toBe('€12.50')
    })

    it('formats a value with two decimal places', () => {
      expect(formatAmount(99.99)).toBe('€99.99')
    })

    it('formats zero', () => {
      expect(formatAmount(0)).toBe('€0.00')
    })

    it('renders a thousands separator for large amounts', () => {
      expect(formatAmount(1234.56)).toBe('€1,234.56')
    })
  })

  describe('locale variations', () => {
    it('uses comma decimals and dot thousands for nl-NL', () => {
      const formatted = formatAmount(1234.56, 'nl-NL')
      expect(formatted).toContain('1.234,56')
      expect(formatted).toContain('€')
    })

    it('places the currency after the number in fr-FR', () => {
      const formatted = formatAmount(42.5, 'fr-FR')
      expect(formatted.indexOf('€')).toBeGreaterThan(formatted.indexOf('42'))
      expect(formatted).toContain('42,50')
    })
  })
})
