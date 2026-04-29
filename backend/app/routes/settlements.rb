# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  hash_branch("api", "settlements") do |r|
    require_auth

    # GET /api/settlements?event_id=xxx - List settlements for an event
    # POST /api/settlements - Create a settlement
    r.is do
      r.get do
        event_id = r.params["event_id"]

        unless event_id
          response.status = 400
          next { error: "event_id is required" }
        end

        event = Event.find(event_id)
        unless event && member_of_workspace?(event.workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        settlements = Settlement.for_event(event_id)
        pool = PoolSerializer.new(membership: current_membership)
        pool.add(:settlement, settlements)
        transfers = SettlementTransfer.for_settlement_ids(settlements.map(&:id))
        pool.add(:settlement_transfer, transfers)

        response.status = 200
        { objects: pool.to_a }
      end

      r.post do
        event_id = r.params["event_id"]

        unless event_id
          response.status = 400
          next { error: "event_id is required" }
        end

        event = Event.find(event_id)
        unless event && member_of_workspace?(event.workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        result = Settlements::Create.call(
          event_id: event_id,
          membership: current_membership,
          workspace_id: event.workspace_id
        )
        handle_result(result, success_status: 201)
      end
    end

    r.on "drift" do
      r.get do
        event_id = r.params["event_id"]

        unless event_id
          response.status = 400
          next { error: "event_id is required" }
        end

        event = Event.find(event_id)
        unless event && member_of_workspace?(event.workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        result = Settlements::PreviewDrift.call(event_id: event_id)
        handle_result(result)
      end
    end

    # /api/settlements/transfers/:id - Toggle paid on a transfer, or get QR code
    r.on "transfers" do
      r.on String do |transfer_id|
        find_result = SettlementTransfer.find_result(transfer_id)
        unless find_result.success?
          error = find_result.failure
          response.status = error.http_status
          next error.to_api_hash
        end
        transfer = find_result.value!

        settlement = Settlement.find(transfer.settlement_id)
        unless settlement
          response.status = 404
          next { error: "Settlement not found" }
        end

        event = Event.find(settlement.event_id)
        unless event && member_of_workspace?(event.workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        # GET /api/settlements/transfers/:id/payment-details - Recipient IBAN, reference, and EPC QR
        r.on "payment-details" do
          r.get do
            result = Settlements::PaymentDetails.call(
              transfer_id: transfer_id,
              membership: current_membership
            )
            # The response can carry the recipient's IBAN (encrypted-at-rest
            # PII) and a base64 QR that embeds it. Don't let any cache —
            # browser bfcache, forward proxy — retain it.
            response["Cache-Control"] = "private, no-store"
            handle_result(result)
          end
        end

        r.put do
          paid = r.params["paid"]

          result = Settlements::MarkPaid.call(
            transfer_id: transfer_id,
            paid: paid == true || paid == "true",
            membership: current_membership,
            workspace_id: event.workspace_id
          )
          handle_result(result)
        end
      end
    end

    # /api/settlements/net-transfers - Workspace-level netted settlements.
    # Reads stay client-side (the pool already has every transfer); these
    # endpoints exist so writes can lock and re-verify the live net before
    # committing.
    r.on "net-transfers" do
      workspace_id = r.params["workspace_id"]
      unless workspace_id && member_of_workspace?(workspace_id)
        response.status = 403
        next { error: "Access denied" }
      end

      r.on "payment-details" do
        r.get do
          counterparty = r.params["counterparty"]
          expected = r.params["expected_amount"]
          result = Settlements::NetPaymentDetails.call(
            workspace_id: workspace_id,
            counterparty_user_id: counterparty,
            expected_amount: expected&.to_f,
            membership: current_membership(workspace_id)
          )
          # Same PII/QR rationale as per-transfer payment-details.
          response["Cache-Control"] = "private, no-store"
          handle_result(result)
        end
      end

      r.on "mark-paid" do
        r.put do
          result = Settlements::MarkNetPaid.call(
            workspace_id: workspace_id,
            counterparty_user_id: r.params["counterparty"],
            expected_amount: r.params["expected_amount"]&.to_f,
            membership: current_membership(workspace_id)
          )
          handle_result(result)
        end
      end

      r.on "mark-unpaid" do
        r.put do
          result = Settlements::MarkNetUnpaid.call(
            workspace_id: workspace_id,
            counterparty_user_id: r.params["counterparty"],
            transfer_ids: Array(r.params["transfer_ids"]),
            membership: current_membership(workspace_id)
          )
          handle_result(result)
        end
      end
    end

    # /api/settlements/:id - Delete a settlement
    r.on String do |id|
      find_result = Settlement.find_result(id)
      unless find_result.success?
        error = find_result.failure
        response.status = error.http_status
        next error.to_api_hash
      end
      settlement = find_result.value!

      event = Event.find(settlement.event_id)
      unless event && member_of_workspace?(event.workspace_id)
        response.status = 403
        next { error: "Access denied" }
      end

      r.delete do
        result = Settlements::Delete.call(
          settlement_id: settlement.id,
          membership: current_membership,
          workspace_id: event.workspace_id
        )
        handle_result(result)
      end
    end
  end
end
