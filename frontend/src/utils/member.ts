import type { PoolMember } from '@/types/pool'

/**
 * Returns initials for a member-like object that has a name and email.
 * Works with PoolMember, AuthUser, or any object with { name, email }.
 *
 * - If name is present: first letter of first + last word, uppercased.
 *   Single-word name returns the first letter only.
 * - If name is absent: first letter of email, uppercased.
 * - If both are absent: '?'.
 */
export function getInitials(member: {
  name: string | null
  email: string
}): string {
  const { name, email } = member
  if (name) {
    const parts = name.trim().split(/\s+/)
    if (parts.length >= 2) {
      const first = parts[0]?.[0] ?? ''
      const last = parts[parts.length - 1]?.[0] ?? ''
      return (first + last).toUpperCase()
    }
    return (parts[0]?.[0] ?? '').toUpperCase()
  }
  return email[0]?.toUpperCase() ?? '?'
}

/**
 * Returns a display name for a user resolved from the object pool.
 * Falls back to 'Unknown' when the userId is null or the member is not found.
 */
export function getMemberName(
  userId: string | null,
  pool: {
    findBy: (
      type: 'member',
      field: 'userId',
      value: string
    ) => PoolMember | undefined
  }
): string {
  if (!userId) return 'Unknown'
  const member = pool.findBy('member', 'userId', userId)
  return member?.name ?? member?.email ?? 'Unknown'
}

/**
 * Returns a display name for a user resolved from a pre-built member map.
 * Used in chore components that receive a Map<userId, PoolMember> as a prop.
 * Falls back to '?' when the userId is not in the map.
 */
export function getMemberNameFromMap(
  userId: string,
  memberMap: Map<string, PoolMember>
): string {
  const member = memberMap.get(userId)
  if (!member) return '?'
  return member.name ?? member.email.split('@')[0] ?? member.email
}
