import { describe, it, expect } from 'vitest'
import { generateVCard } from './vcard'

describe('generateVCard', () => {
  it('generates minimal vCard with name and email', () => {
    const result = generateVCard({
      name: 'Jane Doe',
      email: 'jane@example.com',
      phoneNumber: null,
      birthday: null,
      locationName: null,
      latitude: null,
      longitude: null,
    })

    expect(result).toContain('BEGIN:VCARD')
    expect(result).toContain('VERSION:3.0')
    expect(result).toContain('FN:Jane Doe')
    expect(result).toContain('N:Jane Doe;;;;')
    expect(result).toContain('EMAIL:jane@example.com')
    expect(result).toContain('END:VCARD')
    expect(result).not.toContain('TEL:')
    expect(result).not.toContain('BDAY:')
    expect(result).not.toContain('ADR:')
    expect(result).not.toContain('GEO:')
  })

  it('includes phone number', () => {
    const result = generateVCard({
      name: 'Jane Doe',
      email: 'jane@example.com',
      phoneNumber: '+31612345678',
      birthday: null,
      locationName: null,
      latitude: null,
      longitude: null,
    })

    expect(result).toContain('TEL:+31612345678')
  })

  it('includes birthday', () => {
    const result = generateVCard({
      name: 'Jane Doe',
      email: 'jane@example.com',
      phoneNumber: null,
      birthday: '1990-06-15',
      locationName: null,
      latitude: null,
      longitude: null,
    })

    expect(result).toContain('BDAY:1990-06-15')
  })

  it('includes address and coordinates', () => {
    const result = generateVCard({
      name: 'Jane Doe',
      email: 'jane@example.com',
      phoneNumber: null,
      birthday: null,
      locationName: 'Berlin, Germany',
      latitude: 52.52,
      longitude: 13.405,
    })

    expect(result).toContain('ADR:;;Berlin\\, Germany;;;;')
    expect(result).toContain('GEO:52.52;13.405')
  })

  it('escapes special characters', () => {
    const result = generateVCard({
      name: "O'Brien; Jr.",
      email: 'ob@example.com',
      phoneNumber: null,
      birthday: null,
      locationName: null,
      latitude: null,
      longitude: null,
    })

    expect(result).toContain("FN:O'Brien\\; Jr.")
  })

  it('handles null name', () => {
    const result = generateVCard({
      name: null,
      email: 'nobody@example.com',
      phoneNumber: null,
      birthday: null,
      locationName: null,
      latitude: null,
      longitude: null,
    })

    expect(result).toContain('FN:')
    expect(result).toContain('N:;;;;')
  })

  it('includes all fields together', () => {
    const result = generateVCard({
      name: 'Jane Doe',
      email: 'jane@example.com',
      phoneNumber: '+31612345678',
      birthday: '1990-06-15',
      locationName: 'Berlin, Germany',
      latitude: 52.52,
      longitude: 13.405,
    })

    expect(result).toContain('FN:Jane Doe')
    expect(result).toContain('EMAIL:jane@example.com')
    expect(result).toContain('TEL:+31612345678')
    expect(result).toContain('BDAY:1990-06-15')
    expect(result).toContain('ADR:;;Berlin\\, Germany;;;;')
    expect(result).toContain('GEO:52.52;13.405')
  })

  it('includes address without coordinates when only locationName is provided', () => {
    const result = generateVCard({
      name: 'Jane Doe',
      email: 'jane@example.com',
      phoneNumber: null,
      birthday: null,
      locationName: 'Some Place',
      latitude: null,
      longitude: null,
    })

    expect(result).toContain('ADR:;;Some Place;;;;')
    expect(result).not.toContain('GEO:')
  })

  it('includes GEO without ADR when only coordinates are provided', () => {
    const result = generateVCard({
      name: 'Jane Doe',
      email: 'jane@example.com',
      phoneNumber: null,
      birthday: null,
      locationName: null,
      latitude: 52.52,
      longitude: 13.405,
    })

    expect(result).not.toContain('ADR:')
    expect(result).toContain('GEO:52.52;13.405')
  })

  it('escapes backslashes in name', () => {
    const result = generateVCard({
      name: 'Back\\slash',
      email: 'test@example.com',
      phoneNumber: null,
      birthday: null,
      locationName: null,
      latitude: null,
      longitude: null,
    })

    expect(result).toContain('FN:Back\\\\slash')
  })

  it('escapes commas in location name', () => {
    const result = generateVCard({
      name: 'Test',
      email: 'test@example.com',
      phoneNumber: null,
      birthday: null,
      locationName: 'Street 1, City, Country',
      latitude: null,
      longitude: null,
    })

    expect(result).toContain('ADR:;;Street 1\\, City\\, Country;;;;')
  })

  it('folds long lines at 75 characters', () => {
    const longName = 'A'.repeat(100)
    const result = generateVCard({
      name: longName,
      email: 'test@example.com',
      phoneNumber: null,
      birthday: null,
      locationName: null,
      latitude: null,
      longitude: null,
    })

    // Each physical line should be at most 75 chars (plus the CRLF)
    const lines = result.split('\r\n')
    for (const line of lines) {
      expect(line.length).toBeLessThanOrEqual(75)
    }
  })

  it('uses CRLF line endings', () => {
    const result = generateVCard({
      name: 'Jane',
      email: 'j@example.com',
      phoneNumber: null,
      birthday: null,
      locationName: null,
      latitude: null,
      longitude: null,
    })

    expect(result).toContain('\r\n')
    // Should not have bare LF (without preceding CR)
    const withoutCRLF = result.replace(/\r\n/g, '')
    expect(withoutCRLF).not.toContain('\n')
  })
})
