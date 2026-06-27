import type { Component } from 'vue'
import {
  BanknotesIcon,
  BellIcon,
  CalendarDaysIcon,
  ClipboardDocumentListIcon,
  ShieldCheckIcon,
  UserGroupIcon,
} from '@heroicons/vue/24/outline'

const CATEGORY_OF_KIND: Record<string, string> = {
  new_session: 'security',
  passkey_changed: 'security',
  email_change_completed: 'security',
  workspace_invite: 'workspaces',
  workspace_invite_accepted: 'workspaces',
  member_role_changed: 'workspaces',
  event_created: 'events',
  event_canceled: 'events',
  event_details_changed: 'events',
  poll_closed: 'events',
  chore_reminder: 'chores',
  settlement_created: 'money',
  payment_status_changed: 'money',
  expense_added: 'money',
}

const CATEGORY_ICON: Record<string, Component> = {
  security: ShieldCheckIcon,
  workspaces: UserGroupIcon,
  events: CalendarDaysIcon,
  chores: ClipboardDocumentListIcon,
  money: BanknotesIcon,
}

// Falls back to a bell when a kind isn't recognised — better to render
// the row with a neutral icon than to leave a gap.
export function iconForKind(kind: string): Component {
  const category = CATEGORY_OF_KIND[kind]
  return category ? CATEGORY_ICON[category] : BellIcon
}
