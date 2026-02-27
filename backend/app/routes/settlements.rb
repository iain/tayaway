# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "settlements") do |r|
    user = require_auth

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
        pool = PoolSerializer.new(workspace_id: event.workspace_id)
        settlements.each do |settlement|
          pool.add_settlement(settlement)
          SettlementTransfer.for_settlement(settlement.id).each { |t| pool.add_settlement_transfer(t) }
        end

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
          user_id: user.id,
          workspace_id: event.workspace_id
        )
        handle_result(result, success_status: 201)
      end
    end

    # /api/settlements/transfers/:id - Toggle paid on a transfer, or get QR code
    r.on "transfers" do
      r.on String do |transfer_id|
        # GET /api/settlements/transfers/:id/qr - Generate EPC QR code PNG
        r.on "qr" do
          r.get do
            result = Settlements::GenerateQr.call(
              transfer_id: transfer_id,
              current_user_id: user.id
            )

            if result.success?
              png = result.value!
              response.status = 200
              response["Content-Type"] = "image/png"
              response["Cache-Control"] = "private, max-age=300"
              r.halt [200, { "Content-Type" => "image/png", "Cache-Control" => "private, max-age=300" }, [png]]
            else
              error = result.failure
              response.status = error.http_status
              next error.to_api_hash
            end
          end
        end

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

        r.put do
          unless transfer.to_user_id&.to_s == user.id.to_s
            response.status = 403
            next { error: "Only the recipient can mark a transfer as paid" }
          end

          paid = r.params["paid"]

          result = Settlements::MarkPaid.call(
            transfer_id: transfer_id,
            paid: paid == true || paid == "true",
            workspace_id: event.workspace_id
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
          current_user_id: user.id,
          workspace_id: event.workspace_id
        )
        handle_result(result)
      end
    end
  end
end
