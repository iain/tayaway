import { describe, expect, it } from 'vitest'
import { formatAmount } from './format'

describe('formatAmount', () => {
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

  it('formats a large amount', () => {
    expect(formatAmount(1234.56)).toBe('€1234.56')
  })
})
