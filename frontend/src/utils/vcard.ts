export interface VCardData {
  name: string | null
  email: string
  phoneNumber: string | null
  birthday: string | null // YYYY-MM-DD
  locationName: string | null
  latitude: number | null
  longitude: number | null
}

function escapeValue(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\n/g, '\\n')
}

// RFC 6350: lines must not exceed 75 octets; fold with CRLF + space
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

export function generateVCard(data: VCardData): string {
  const lines: string[] = ['BEGIN:VCARD', 'VERSION:3.0']

  const name = data.name ?? ''
  lines.push(`FN:${escapeValue(name)}`)
  lines.push(`N:${escapeValue(name)};;;;`)

  lines.push(`EMAIL:${escapeValue(data.email)}`)

  if (data.phoneNumber) {
    lines.push(`TEL:${escapeValue(data.phoneNumber)}`)
  }

  if (data.birthday) {
    // BDAY format: YYYY-MM-DD
    lines.push(`BDAY:${data.birthday}`)
  }

  if (data.locationName) {
    // ADR: PO Box;Extended;Street;City;Region;PostalCode;Country
    // Put locationName in the street field
    lines.push(`ADR:;;${escapeValue(data.locationName)};;;;`)
  }

  if (data.latitude != null && data.longitude != null) {
    lines.push(`GEO:${data.latitude};${data.longitude}`)
  }

  lines.push('END:VCARD')

  return lines.map(foldLine).join('\r\n')
}

export function downloadVCard(filename: string, content: string): void {
  const blob = new Blob([content], { type: 'text/vcard;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}
