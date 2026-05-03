// Mirrors the backend's MOD97-10 + structural validation in
// backend/app/services/users/update_profile.rb so the user gets immediate
// feedback while typing, and the server's the only thing that gets to say
// "really truly valid" — but doesn't have to round-trip every keystroke.

const STRUCTURAL = /^[A-Z]{2}\d{2}[A-Z0-9]{4,30}$/

export function normalizeIban(raw: string): string {
  return raw.replace(/\s+/g, '').toUpperCase()
}

// "NL91ABNA0417164300" → "NL91 ABNA 0417 1643 00"
export function formatIban(raw: string): string {
  const normalized = normalizeIban(raw)
  return normalized.replace(/(.{4})(?!$)/g, '$1 ')
}

// Returns null if the value is plausibly a valid IBAN (or empty), otherwise a
// short reason. Empty string is "no value yet" — Save buttons should disable
// on emptiness separately, not call this and complain about format.
export function validateIban(raw: string): string | null {
  const normalized = normalizeIban(raw)
  if (normalized === '') return null

  if (!STRUCTURAL.test(normalized)) {
    return 'Invalid IBAN format'
  }

  // MOD97-10: move the first four chars to the end, replace letters with
  // their A=10..Z=35 numeric values, the resulting integer must be ≡ 1 mod 97.
  const rearranged = normalized.slice(4) + normalized.slice(0, 4)
  let remainder = 0
  for (const ch of rearranged) {
    const value =
      ch >= 'A' && ch <= 'Z' ? ch.charCodeAt(0) - 55 : ch.charCodeAt(0) - 48
    // Two-digit values from letters need to be folded one digit at a time
    // to avoid 64-bit overflow on long IBANs.
    if (value >= 10) {
      remainder = (remainder * 10 + Math.floor(value / 10)) % 97
      remainder = (remainder * 10 + (value % 10)) % 97
    } else {
      remainder = (remainder * 10 + value) % 97
    }
  }

  return remainder === 1 ? null : 'Invalid IBAN checksum'
}
