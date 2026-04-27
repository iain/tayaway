import type { Permission } from '@/types/pool'

type Permissions = Record<string, Permission | string[]> | undefined

export function can(permissions: Permissions, action: string): boolean {
  if (!permissions) return false
  const perm = permissions[action]
  if (!perm || Array.isArray(perm)) return false
  return perm.allowed
}

export function permissionReason(
  permissions: Permissions,
  action: string
): string | undefined {
  if (!permissions) return undefined
  const perm = permissions[action]
  if (!perm || Array.isArray(perm)) return undefined
  return perm.reason
}

// UX behavior for a denied permission
export type PermissionUx =
  | { behavior: 'enabled' }
  | { behavior: 'hidden' }
  | { behavior: 'disabled'; tooltip: string }
  | { behavior: 'modal'; message: string }

// Reasons that should hide the element entirely. If the user has no path to
// making the action succeed here-and-now, we don't want a disabled affordance
// whispering about it — either another affordance (like Revert) is the right
// path, or the action simply isn't theirs to take.
const HIDE_REASONS = new Set([
  'not_owner',
  'not_creator',
  'not_event_owner',
  'not_creator_or_event_owner',
  'not_admin_or_owner',
  'not_sender',
  'cannot_change_own_role',
  'cannot_change_owner',
  'not_settled',
  'revert_of_revert',
  'already_paid',
])

// Reasons that should show a disabled element with a tooltip — the user is
// the right person but a temporary/fixable condition blocks them.
const DISABLE_REASONS: Record<string, string> = {}

// Reasons that should show an explanation modal — the user needs context
// about what to do next.
const MODAL_REASONS: Record<string, string> = {
  has_expenses:
    'This event has expenses or settlements. Settle up and delete expenses before deleting the event.',
  not_recipient:
    'Only the person receiving the money can mark a transfer as paid.',
  locked_in_followup:
    'A follow-up settlement was issued treating this transfer as paid. Delete the follow-up first if you really need to undo it.',
  settled:
    'This expense is locked into a settlement. Use Revert to offset it on the next settlement.',
  is_revert:
    'This is a revert entry. To change your mind, file a fresh expense instead.',
  not_tip: 'Only the most recent settlement can be deleted.',
  superseded: 'This transfer was rolled into a follow-up settlement.',
}

export function permissionUx(
  permissions: Permissions,
  action: string
): PermissionUx {
  if (can(permissions, action)) {
    return { behavior: 'enabled' }
  }

  const reason = permissionReason(permissions, action)

  if (!reason) {
    return { behavior: 'hidden' }
  }

  if (HIDE_REASONS.has(reason)) {
    return { behavior: 'hidden' }
  }

  if (reason in MODAL_REASONS) {
    return { behavior: 'modal', message: MODAL_REASONS[reason] }
  }

  if (reason in DISABLE_REASONS) {
    return { behavior: 'disabled', tooltip: DISABLE_REASONS[reason] }
  }

  // Unknown reason: disable and show the raw reason so it's visible
  // during development that a translation is missing.
  return { behavior: 'disabled', tooltip: reason }
}
