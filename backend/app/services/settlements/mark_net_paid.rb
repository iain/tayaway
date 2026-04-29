# frozen_string_literal: true

module Settlements
  # Marks all underlying per-event transfers between the caller and one
  # counterparty as paid, atomically. Used by the workspace-level "Settle
  # up" page where balances across events are netted by counterparty pair.
  #
  # Authorization: only the *net recipient* may invoke. The dominant
  # direction is derived from the active transfers, not supplied by the
  # caller, so a request with no real obligation simply 409s. Callers also
  # pass an `expected_amount` they saw on screen; if the live net no longer
  # matches (a top-up settlement landed in between), we 409 rather than
  # silently mark the new balance as paid.
  module MarkNetPaid
    class << self
      def call(workspace_id:, counterparty_user_id:, expected_amount:, membership:)
        Auditable.around(
          service: "Settlements::MarkNetPaid",
          actor: membership,
          subject_type: "settlement_transfer",
          workspace_id: workspace_id,
          context: {
            counterparty_user_id: counterparty_user_id.to_s,
            expected_amount: expected_amount
          }
        ) do
          Success()
            .bind { validate(counterparty_user_id, expected_amount, membership) }
            .bind { settle(workspace_id, membership, counterparty_user_id, expected_amount) }
        end
      end

      private

      def validate(counterparty_user_id, expected_amount, membership)
        if counterparty_user_id.nil? || counterparty_user_id.to_s.strip.empty?
          Failure(ServiceError.validation("counterparty_user_id is required"))
        elsif counterparty_user_id.to_s == membership.user_id.to_s
          Failure(ServiceError.validation("Cannot settle a balance with yourself"))
        elsif expected_amount.nil?
          Failure(ServiceError.validation("expected_amount is required"))
        else
          Success()
        end
      end

      def settle(workspace_id, membership, counterparty_user_id, expected_amount)
        failure = nil
        updated_ids = []
        now = Time.now

        DB.transaction do
          # Workspace-scoped advisory lock — serialises any concurrent
          # MarkNetPaid run in this workspace, eliminating the lock-and-list
          # race where two callers each compute their own event set and lock
          # only what they observed. Concurrency with Settlements::Create on
          # an event we haven't seen yet is still possible; that case is
          # caught by the expected_amount drift check below, since
          # WorkspaceNet.compute_pair re-queries under this lock and any new
          # transfer shifts the live amount away from what the caller saw.
          DB.get(Sequel.function(:pg_advisory_xact_lock,
                                 Sequel.function(:hashtext, "mark_net_paid:#{workspace_id}")
                                )
                )

          involved_event_ids = DB[:settlement_transfers]
                               .join(:settlements, id: :settlement_id)
                               .join(:events, id: Sequel[:settlements][:event_id])
                               .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
                               .where(Sequel[:settlement_transfers][:superseded_at] => nil)
                               .where(Sequel[:settlement_transfers][:paid_at] => nil)
                               .where(pair_filter(membership.user_id, counterparty_user_id))
                               .distinct
                               .select_map(Sequel[:settlements][:event_id])

          if involved_event_ids.empty?
            failure = Failure(ServiceError.conflict("Nothing to settle — no active balance with this person"))
            raise Sequel::Rollback
          end

          # Hold the same per-event lock Settlements::Create takes, so an
          # in-flight top-up on one of these events doesn't supersede our
          # rows between the recompute and the UPDATE.
          DB[:events].where(id: involved_event_ids).for_update.all

          net = WorkspaceNet.compute_pair(
            workspace_id: workspace_id,
            user_a: membership.user_id,
            user_b: counterparty_user_id
          )

          if net.nil?
            failure = Failure(ServiceError.conflict("Nothing to settle — the balance is even"))
            raise Sequel::Rollback
          end

          # Either party of the pair may attest. The dominant direction
          # determines who's owed what, but both sides can close the loop —
          # the sender after paying, the recipient after receiving. The
          # acting user goes onto each row so notifications and the UI can
          # show who marked paid.
          caller_in_pair = [net[:from_user_id], net[:to_user_id]].include?(membership.user_id.to_s)
          unless caller_in_pair
            failure = Failure(ServiceError.forbidden("not_pair_member"))
            raise Sequel::Rollback
          end

          if (net[:amount] - expected_amount.to_f).abs >= WorkspaceNet::BALANCE_EPSILON
            failure = Failure(ServiceError.conflict(
                                "Balance has changed since you opened this page (was €#{format("%.2f", expected_amount.to_f)}, now €#{format("%.2f", net[:amount])}). Refresh and try again."
                              )
                             )
            raise Sequel::Rollback
          end

          DB[:settlement_transfers]
            .where(id: net[:underlying_transfer_ids])
            .update(paid_at: now, paid_by_user_id: membership.user_id, updated_at: now)
          updated_ids = net[:underlying_transfer_ids]
        end

        return failure if failure

        updated_ids.each do |id|
          Broadcaster.object_changed("settlement_transfer", id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(membership: membership)
        pool.add(:settlement_transfer, updated_ids.filter_map { |id| SettlementTransfer.find(id) })
        Success({ objects: pool.to_a })
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
