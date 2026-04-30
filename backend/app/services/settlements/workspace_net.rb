# frozen_string_literal: true

module Settlements
  # Nets active per-event transfers between a single pair of users in a
  # workspace. "Active" means non-superseded and unpaid: paid rows already
  # cleared, superseded rows have been rolled into a follow-up settlement.
  #
  # The returned amount is the absolute net; `from_user_id`/`to_user_id`
  # describe the dominant direction. `underlying_transfer_ids` lists every
  # row that contributes to the net — including rows in the counter
  # direction — because Settlements::MarkNetPaid needs to settle all of
  # them in one transaction.
  #
  # Limited to same-pair netting on purpose. Cross-pair restructuring (e.g.
  # collapsing A→B + B→C into A→C) would sever the link from the suggested
  # transfer to the per-event rows it represents.
  module WorkspaceNet
    BALANCE_EPSILON = BalanceMath::BALANCE_EPSILON

    class << self
      def compute_pair(workspace_id:, user_a:, user_b:)
        a_id = user_a.to_s
        b_id = user_b.to_s
        return nil if a_id == b_id

        rows = active_transfers_between(workspace_id, a_id, b_id)
        return nil if rows.empty?

        signed_total = 0.0
        rows.each do |row|
          from_id = row[:from_user_id].to_s
          to_id = row[:to_user_id].to_s
          amount = row[:amount].to_f
          if from_id == a_id && to_id == b_id
            signed_total += amount
          elsif from_id == b_id && to_id == a_id
            signed_total -= amount
          end
        end

        amount = signed_total.abs.round(2).to_f
        return nil if amount < BALANCE_EPSILON

        from_id, to_id = signed_total.positive? ? [a_id, b_id] : [b_id, a_id]
        {
          from_user_id: from_id,
          to_user_id: to_id,
          amount: amount,
          underlying_transfer_ids: rows.map { |r| r[:id].to_s }
        }
      end

      private

      def active_transfers_between(workspace_id, user_a, user_b)
        DB[:settlement_transfers]
          .join(:settlements, id: :settlement_id)
          .join(:events, id: Sequel[:settlements][:event_id])
          .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
          .where(Sequel[:settlement_transfers][:superseded_at] => nil)
          .where(Sequel[:settlement_transfers][:paid_at] => nil)
          .where(
            Sequel.|(
              {
                Sequel[:settlement_transfers][:from_user_id] => user_a,
                Sequel[:settlement_transfers][:to_user_id] => user_b
              },
              {
                Sequel[:settlement_transfers][:from_user_id] => user_b,
                Sequel[:settlement_transfers][:to_user_id] => user_a
              }
            )
          )
          .select_all(:settlement_transfers)
          .order(Sequel[:settlement_transfers][:created_at])
          .all
      end
    end
  end
end
