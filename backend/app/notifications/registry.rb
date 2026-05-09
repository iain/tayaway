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
      workspace_invite: Kinds::WorkspaceInvite,
      poll_closed: Kinds::PollClosed,
      settlement_created: Kinds::SettlementCreated,
      transfer_paid: Kinds::TransferPaid,
      expense_added: Kinds::ExpenseAdded,
      event_details_changed: Kinds::EventDetailsChanged
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
