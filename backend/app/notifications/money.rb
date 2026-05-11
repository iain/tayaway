# frozen_string_literal: true

module Notifications
  # Currency formatting shared by every money-themed kind (expenses,
  # settlements, payment status). Single source of truth so a future
  # per-workspace currency or locale change is one edit, not a hunt
  # across kinds.
  module Money
    class << self
      def format_amount(amount)
        format("€%.2f", amount)
      end
    end
  end
end
