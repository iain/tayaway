# frozen_string_literal: true

# Expense participants are managed exclusively through Expenses::Update —
# there is no route to delete or edit one directly, so the policy publishes
# no actions. The class still exists because the object registry expects a
# policy entry for every type, and PermissionAttacher relies on it being
# resolvable.
class ExpenseParticipantPolicy
  include Policy

  ACTIONS = [].freeze

  def initialize(_participant, **)
  end
end
