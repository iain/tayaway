import { describe, it, expect } from 'vitest'
import { formatIban, normalizeIban, validateIban } from './iban'

describe('normalizeIban', () => {
  it('uppercases and strips whitespace', () => {
    expect(normalizeIban('  nl91 abna 0417 1643 00  ')).toBe(
      'NL91ABNA0417164300'
    )
  })
})

describe('formatIban', () => {
  it('groups in fours with spaces', () => {
    expect(formatIban('NL91ABNA0417164300')).toBe('NL91 ABNA 0417 1643 00')
  })

  it('reflows when the user has odd spacing', () => {
    expect(formatIban('nl91abna04 171643 00')).toBe('NL91 ABNA 0417 1643 00')
  })

  it('leaves an in-progress IBAN alone gracefully', () => {
    expect(formatIban('NL91A')).toBe('NL91 A')
  })

  it('returns empty for empty input', () => {
    expect(formatIban('')).toBe('')
  })
})

describe('validateIban', () => {
  it('returns null for a valid IBAN', () => {
    expect(validateIban('NL91 ABNA 0417 1643 00')).toBeNull()
  })

  it('returns null for empty input — emptiness is for Save buttons to gate', () => {
    expect(validateIban('')).toBeNull()
    expect(validateIban('   ')).toBeNull()
  })

  it('rejects bad structure', () => {
    // First two chars must be letters, then digits, then alphanumeric.
    expect(validateIban('1234 5678')).toBe('Invalid IBAN format')
    expect(validateIban('NLAB 0000')).toBe('Invalid IBAN format')
  })

  it('rejects bad checksum', () => {
    // Valid structure, wrong check digits.
    expect(validateIban('NL00 FAKE 1234 5678 90')).toBe('Invalid IBAN checksum')
  })

  it('handles long IBANs without overflow', () => {
    // 32-char Maltese IBAN — long enough to overflow 64-bit ints if naively
    // converted via toInt().
    expect(validateIban('MT84 MALT 0110 0001 2345 MTLC AST0 01S')).toBeNull()
  })
})
