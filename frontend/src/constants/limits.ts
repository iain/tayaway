/**
 * Client-side text-length caps.
 *
 * Mirror of the backend's `ValidationLimits`
 * (backend/app/services/validation_limits.rb) — the server enforces the same
 * caps and rejects anything longer, so the client value is a UX guardrail, not
 * the source of truth. Keep the two in sync when either changes.
 */
export const TEXT_LIMITS = {
  /** Names, titles, locations: events, task lists, chores, members, profiles. */
  name: 255,
  /** One-line content that lives in a list row: task items, chore notes. */
  shortText: 500,
  /** Long free-text: event descriptions. */
  longText: 5000,
  /** Vote comments. */
  comment: 1000,
  /** Phone numbers. */
  phone: 50,
} as const
