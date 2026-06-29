import tzlookup from 'tz-lookup'

// Kept separate from utils/timezone so the tz-lookup boundary data (which the
// rest of the app never needs) only lands in the event-form chunk that imports
// this.

/** The IANA zone for a coordinate, or null if it can't be resolved. */
export function timezoneForCoordinates(
  lat: number | null | undefined,
  lng: number | null | undefined
): string | null {
  if (lat == null || lng == null) return null
  try {
    return tzlookup(lat, lng)
  } catch {
    // tz-lookup throws for out-of-range coordinates.
    return null
  }
}

/**
 * The zone an event lands in for a location, by the same precedence the server
 * applies: the location-derived zone, else the workspace default, else null
 * (nothing resolvable yet). Drives the "Times shown in …" hint behind the
 * Automatic option in both the create wizard and the event page.
 */
export function effectiveEventZone(
  lat: number | null | undefined,
  lng: number | null | undefined,
  workspaceZone: string | null | undefined
): string | null {
  return timezoneForCoordinates(lat, lng) ?? workspaceZone ?? null
}
