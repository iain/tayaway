# frozen_string_literal: true

module Notifications
  # Single source of truth for which user-facing notification kinds exist.
  # Adding a kind is a registry edit plus a new file under
  # `app/notifications/kinds/` — no schema change, no preferences backfill
  # (absent preference rows mean "use the kind's defaults"). Auth-flow
  # mail (login link, email-change verification) deliberately stays in
  # `Mailers::*`: it isn't user-configurable, doesn't appear in the
  # preferences UI, and conceptually lives with the auth code rather than
  # the notification system.
  module Registry
    KINDS = {
      new_session: Kinds::NewSession,
      passkey_changed: Kinds::PasskeyChanged,
      email_change_completed: Kinds::EmailChangeCompleted,
      workspace_invite: Kinds::WorkspaceInvite,
      workspace_invite_accepted: Kinds::WorkspaceInviteAccepted,
      member_role_changed: Kinds::MemberRoleChanged,
      poll_closed: Kinds::PollClosed,
      event_created: Kinds::EventCreated,
      event_canceled: Kinds::EventCanceled,
      event_details_changed: Kinds::EventDetailsChanged,
      settlement_created: Kinds::SettlementCreated,
      payment_status_changed: Kinds::PaymentStatusChanged,
      expense_added: Kinds::ExpenseAdded,
      chore_reminder: Kinds::ChoreReminder
    }.freeze

    class << self
      # Raises KeyError on an unknown key — the caller list is finite and
      # internal, so a typo should crash loudly rather than silently no-op.
      def fetch(key)
        KINDS.fetch(key.to_sym)
      end

      def all
        KINDS.values
      end
    end
  end
end
