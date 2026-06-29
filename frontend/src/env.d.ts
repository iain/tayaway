declare module '@fontsource-variable/inter'

declare module 'tz-lookup' {
  /** Nearest IANA timezone for a coordinate; throws on out-of-range input. */
  export default function tzlookup(lat: number, lon: number): string
}
