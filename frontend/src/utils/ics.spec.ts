import { describe, it, expect } from 'vitest'
import { generateIcs } from './ics'

const base = {
  uid: 'abc-123',
  summary: 'Team Offsite',
  description: null,
  startDate: null,
  endDate: null,
  createdAt: '2026-02-01T10:00:00.000Z',
}

describe('generateIcs', () => {
  it('includes required ICS headers', () => {
    const ics = generateIcs(base)
    expect(ics).toContain('BEGIN:VCALENDAR')
    expect(ics).toContain('VERSION:2.0')
    expect(ics).toContain('BEGIN:VEVENT')
    expect(ics).toContain('END:VEVENT')
    expect(ics).toContain('END:VCALENDAR')
  })

  it('includes event UID and summary', () => {
    const ics = generateIcs(base)
    expect(ics).toContain('UID:abc-123@tayaway')
    expect(ics).toContain('SUMMARY:Team Offsite')
  })

  it('includes CREATED from createdAt', () => {
    const ics = generateIcs(base)
    expect(ics).toContain('CREATED:20260201T100000Z')
  })

  it('omits DTSTART/DTEND when no dates', () => {
    const ics = generateIcs(base)
    expect(ics).not.toContain('DTSTART')
    expect(ics).not.toContain('DTEND')
  })

  it('includes all-day DTSTART and DTEND when dates are set', () => {
    const ics = generateIcs({
      ...base,
      startDate: '2026-03-10',
      endDate: '2026-03-12',
    })
    expect(ics).toContain('DTSTART;VALUE=DATE:20260310')
    // DTEND is exclusive: endDate + 1 day
    expect(ics).toContain('DTEND;VALUE=DATE:20260313')
  })

  it('uses startDate for DTEND when endDate equals startDate', () => {
    const ics = generateIcs({
      ...base,
      startDate: '2026-04-01',
      endDate: '2026-04-01',
    })
    expect(ics).toContain('DTSTART;VALUE=DATE:20260401')
    expect(ics).toContain('DTEND;VALUE=DATE:20260402')
  })

  it('includes description when provided', () => {
    const ics = generateIcs({ ...base, description: 'Bring snacks' })
    expect(ics).toContain('DESCRIPTION:Bring snacks')
  })

  it('omits DESCRIPTION when null', () => {
    const ics = generateIcs(base)
    expect(ics).not.toContain('DESCRIPTION')
  })

  it('escapes special characters in summary', () => {
    const ics = generateIcs({ ...base, summary: 'Party, Fun; & More\\stuff' })
    expect(ics).toContain('SUMMARY:Party\\, Fun\\; & More\\\\stuff')
  })

  it('escapes newlines in description', () => {
    const ics = generateIcs({ ...base, description: 'Line one\nLine two' })
    expect(ics).toContain('DESCRIPTION:Line one\\nLine two')
  })

  it('uses CRLF line endings', () => {
    const ics = generateIcs(base)
    expect(ics).toContain('\r\n')
    expect(ics.split('\r\n').length).toBeGreaterThan(1)
  })

  it('folds lines longer than 75 characters', () => {
    const longSummary = 'A'.repeat(100)
    const ics = generateIcs({ ...base, summary: longSummary })
    for (const line of ics.split('\r\n')) {
      expect(line.length).toBeLessThanOrEqual(75)
    }
  })
})
