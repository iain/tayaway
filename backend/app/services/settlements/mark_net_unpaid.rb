# frozen_string_literal: true

module Settlements
  # Reverses a workspace-level mark-paid for a given counterparty pair. Used
  # by the "Unmark" affordance on the Recently settled section so a sender
  # who attested too early — or a recipient who didn't actually receive —
  # can flip the obligation back without diving into each per-event page.
  #
  # Authorization: same as MarkNetPaid — caller must be one of the two
  # parties. The transfer ids are passed by the caller (they're known from
  # the recent-settled card), but every row is re-checked under the lock to
  # ensure it truly belongs to the (workspace, pair) and is currently paid.
  module MarkNetUnpaid
    class << self
      def call(workspace_id:, counterparty_user_id:, transfer_ids:, membership:)
        Auditable.around(
          service: "Settlements::MarkNetUnpaid",
          actor: membership,
          subject_type: "settlement_transfer",
          workspace_id: workspace_id,
          context: {
            counterparty_user_id: counterparty_user_id.to_s,
            transfer_count: Array(transfer_ids).size
          }
        ) do
          Success()
            .bind { validate(counterparty_user_id, transfer_ids, membership) }
            .bind { unmark(workspace_id, membership, counterparty_user_id, Array(transfer_ids)) }
        end
      end

      private

      def validate(counterparty_user_id, transfer_ids, membership)
        if counterparty_user_id.nil? || counterparty_user_id.to_s.strip.empty?
          Failure(ServiceError.validation("counterparty_user_id is required"))
        elsif counterparty_user_id.to_s == membership.user_id.to_s
          Failure(ServiceError.validation("Cannot settle a balance with yourself"))
        elsif Array(transfer_ids).empty?
          Failure(ServiceError.validation("transfer_ids is required"))
        else
          Success()
        end
      end

      def unmark(workspace_id, membership, counterparty_user_id, transfer_ids)
        failure = nil
        updated_ids = []
        notify_payload = nil
        now = Time.now

        DB.transaction do
          # Same advisory lock MarkNetPaid takes — serialises any concurrent
          # mark/unmark attempt on the same workspace pair.
          DB.get(Sequel.function(:pg_advisory_xact_lock,
                                 Sequel.function(:hashtext, "mark_net_paid:#{workspace_id}")
                                )
                )

          # Resolve the rows the caller asked us to unmark, scoped to this
          # workspace, this pair, and currently paid. Anything that doesn't
          # match is silently dropped — the caller is allowed to be slightly
          # stale (the recent-settled card was a snapshot).
          rows = DB[:settlement_transfers]
                 .join(:settlements, id: :settlement_id)
                 .join(:events, id: Sequel[:settlements][:event_id])
                 .where(Sequel[:settlement_transfers][:id] => transfer_ids)
                 .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
                 .exclude(Sequel[:settlement_transfers][:paid_at] => nil)
                 .where(pair_filter(membership.user_id, counterparty_user_id))
                 .select_all(:settlement_transfers)
                 .for_update
                 .all

          if rows.empty?
            failure = Failure(ServiceError.conflict("Nothing to unmark — these transfers aren't paid or don't match this pair"))
            raise Sequel::Rollback
          end

          # Block the same case the per-event policy blocks: a paid transfer
          # whose settlement has a successor was treated as paid in the
          # follow-up's balance math. Unmarking would silently desync the
          # chain, so reject the whole batch.
          locked_settlements = DB[:settlements]
                               .where(previous_settlement_id: rows.map { |r| r[:settlement_id] })
                               .select_map(:previous_settlement_id)
                               .to_set
          if rows.any? { |r| locked_settlements.include?(r[:settlement_id]) }
            failure = Failure(ServiceError.forbidden("locked_in_followup"))
            raise Sequel::Rollback
          end

          updated_ids = rows.map { |r| r[:id] }
          DB[:settlement_transfers]
            .where(id: updated_ids)
            .update(paid_at: nil, paid_by_user_id: nil, updated_at: now)
          notify_payload = build_notify_payload(rows, membership.user_id)
        end

        return failure if failure

        updated_ids.each do |id|
          Broadcaster.object_changed("settlement_transfer", id)
        end

        if notify_payload
          Settlements::OnUnpaid.call(
            workspace_id: workspace_id,
            actor_user_id: membership.user_id,
            counterparty_user_id: counterparty_user_id,
            amount: notify_payload[:amount],
            actor_role: notify_payload[:actor_role]
          )
        end

        pool = PoolSerializer.new(membership: membership)
        pool.add(:settlement_transfer, updated_ids.filter_map { |id| SettlementTransfer.find(id) })
        Success({ objects: pool.to_a })
      end

      # Determines the actor's role (debtor vs creditor) and total
      # amount across the unmarked rows from the actor's perspective:
      # positive net = actor was paying (debtor), negative = receiving
      # (creditor). Mirrors what `compute_pair` does for MarkNetPaid,
      # but inline because we already have the rows in hand.
      def build_notify_payload(rows, actor_user_id)
        actor_id = actor_user_id.to_s
        signed = rows.sum do |r|
          r[:from_user_id].to_s == actor_id ? r[:amount].to_f : -r[:amount].to_f
        end
        amount = signed.abs.round(2)
        return nil if amount.zero?

        { amount: amount, actor_role: signed.positive? ? "debtor" : "creditor" }
      end

      def pair_filter(user_a, user_b)
        Sequel.|(
          {
            Sequel[:settlement_transfers][:from_user_id] => user_a.to_s,
            Sequel[:settlement_transfers][:to_user_id] => user_b.to_s
          },
          {
            Sequel[:settlement_transfers][:from_user_id] => user_b.to_s,
            Sequel[:settlement_transfers][:to_user_id] => user_a.to_s
          }
        )
      end
    end
  end
end
