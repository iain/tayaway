/**
 * Format a euro amount as a locale-aware currency string. Mirrors what the
 * visible `<LedgerAmount>` renders, so screen-reader labels and other
 * string-context callers see the same digits, thousands separator, decimal
 * style, and currency placement the sighted reader does.
 *
 * The locale defaults to `'en-US'` for one-shot callers (tests, fallbacks).
 * Vue components should pass `useLocale().value` so a future user choice
 * propagates everywhere.
 */
export function formatAmount(amount: number, locale: string = 'en-US'): string {
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: 'EUR',
  }).format(amount)
}

/** The shared "+N guest" / "+N guests" label for a plus-ones count. */
export function formatGuestCount(guests: number): string {
  return `+${guests} guest${guests === 1 ? '' : 's'}`
}
