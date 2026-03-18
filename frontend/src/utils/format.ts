/**
 * Format a numeric euro amount as a currency string.
 * e.g. 12.5 → "€12.50"
 */
export function formatAmount(amount: number): string {
  return `€${amount.toFixed(2)}`
}
