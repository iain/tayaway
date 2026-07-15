import { addDays, nowIso } from '@/utils/date'

export interface IcsEventData {
  uid: string
  summary: string
  description: string | null
  startDate: string | null // YYYY-MM-DD
  endDate: string | null // YYYY-MM-DD
  location: string | null
  createdAt: string
}

function escapeText(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\n/g, '\\n')
}

// RFC 5545: lines must not exceed 75 octets; fold with CRLF + space
function foldLine(line: string): string {
  if (line.length <= 75) return line
  let result = line.slice(0, 75)
  let remaining = line.slice(75)
  while (remaining.length > 0) {
    result += '\r\n ' + remaining.slice(0, 74)
    remaining = remaining.slice(74)
  }
  return result
}

function formatDate(isoDate: string): string {
  return isoDate.replace(/-/g, '')
}

// DTEND for all-day events is exclusive, so add one day.
function formatDateExclusive(isoDate: string): string {
  return formatDate(addDays(isoDate, 1))
}

function formatDtstamp(isoString: string): string {
  return isoString.replace(/[-:]/g, '').replace(/\.\d{3}/, '')
}

export function generateIcs(event: IcsEventData): string {
  const lines: string[] = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Tayaway//Tayaway//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${event.uid}@tayaway`,
    `DTSTAMP:${formatDtstamp(nowIso())}`,
    `CREATED:${formatDtstamp(event.createdAt)}`,
    `SUMMARY:${escapeText(event.summary)}`,
  ]

  if (event.description) {
    lines.push(`DESCRIPTION:${escapeText(event.description)}`)
  }

  if (event.location) {
    lines.push(`LOCATION:${escapeText(event.location)}`)
  }

  if (event.startDate) {
    lines.push(`DTSTART;VALUE=DATE:${formatDate(event.startDate)}`)
    const endDate = event.endDate ?? event.startDate
    lines.push(`DTEND;VALUE=DATE:${formatDateExclusive(endDate)}`)
  }

  lines.push('END:VEVENT', 'END:VCALENDAR')

  return lines.map(foldLine).join('\r\n')
}

export function downloadIcs(filename: string, content: string): void {
  const blob = new Blob([content], { type: 'text/calendar;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}
