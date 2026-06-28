// Timezone-aware helpers built on the Intl API — no heavy date library. The
// app reckons event-bound times (chore times, "today") in the *event's* zone,
// not the viewer's device zone, so a traveller sees the event's day and time.

/** The viewer's own device zone, e.g. "Europe/Amsterdam". */
export function deviceTimezone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone
}

const FORMATTERS = new Map<string, Intl.DateTimeFormat>()

function formatter(zone: string): Intl.DateTimeFormat {
  let f = FORMATTERS.get(zone)
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone: zone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
    FORMATTERS.set(zone, f)
  }
  return f
}

interface WallParts {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second: number
}

function partsInZone(epochMs: number, zone: string): WallParts {
  const parts = formatter(zone).formatToParts(new Date(epochMs))
  const m: Record<string, string> = {}
  for (const p of parts) if (p.type !== 'literal') m[p.type] = p.value
  return {
    year: Number(m.year),
    month: Number(m.month),
    day: Number(m.day),
    // Some engines emit "24" for midnight under h23 — normalise to 0.
    hour: Number(m.hour) % 24,
    minute: Number(m.minute),
    second: Number(m.second),
  }
}

// The zone's UTC offset (ms) at a given instant — how far its wall clock runs
// ahead of UTC.
function offsetMs(epochMs: number, zone: string): number {
  const p = partsInZone(epochMs, zone)
  const asUTC = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second)
  return asUTC - epochMs
}

function pad(n: number): string {
  return String(n).padStart(2, '0')
}

/** "YYYY-MM-DD" civil date in `zone` at the given instant. */
export function zonedDateString(epochMs: number, zone: string): string {
  const p = partsInZone(epochMs, zone)
  return `${p.year}-${pad(p.month)}-${pad(p.day)}`
}

/**
 * Absolute epoch (ms) for a wall-clock time in `zone`. `time` is "HH:MM" or
 * null (treated as 00:00). DST edges resolve deterministically — exact to the
 * minute everywhere except the rare transition hour, which is fine for day
 * boundaries and "is it past now" checks.
 */
export function wallClockToEpoch(
  date: string,
  time: string | null,
  zone: string
): number {
  const [y, mo, d] = date.split('-').map(Number) as [number, number, number]
  const [h, mi] = (time ? time.split(':').map(Number) : [0, 0]) as [
    number,
    number,
  ]
  const asUTC = Date.UTC(y, mo - 1, d, h, mi)
  // First guess from the offset at the as-if-UTC instant, then correct once in
  // case that instant landed on the other side of a DST transition.
  const off1 = offsetMs(asUTC, zone)
  let epoch = asUTC - off1
  const off2 = offsetMs(epoch, zone)
  if (off2 !== off1) epoch = asUTC - off2
  return epoch
}

/** "HH:MM" (24h) wall-clock of an instant in `zone`. */
export function formatTimeInZone(epochMs: number, zone: string): string {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: zone,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(new Date(epochMs))
}

/** Short zone name for an instant, e.g. "CEST" or "GMT+9". */
export function formatZoneAbbrev(epochMs: number, zone: string): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: zone,
    timeZoneName: 'short',
    hour: '2-digit',
  }).formatToParts(new Date(epochMs))
  return parts.find((p) => p.type === 'timeZoneName')?.value ?? ''
}

/** Calendar arithmetic on a "YYYY-MM-DD" string (zone-independent). */
export function addDays(date: string, days: number): string {
  const [y, mo, d] = date.split('-').map(Number) as [number, number, number]
  const t = new Date(Date.UTC(y, mo - 1, d + days))
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`
}
