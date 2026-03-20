# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "expenses") do |r|
    user = require_auth

    # GET /api/expenses?event_id=xxx - List expenses for an event
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

        expenses = Expense.for_event(event_id)
        pool = PoolSerializer.new(workspace_id: event.workspace_id)
        pool.add_expenses_batch(expenses)

        response.status = 200
        { objects: pool.to_a }
      end

      # POST /api/expenses - Create a new expense
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

        amount_param = r.params["amount"]
        amount = amount_param ? amount_param.to_f : nil

        participant_ids = r.params["participant_ids"]
        participant_ids = Array(participant_ids) if participant_ids

        result = Expenses::Create.call(
          event_id: event_id,
          user_id: user.id,
          workspace_id: event.workspace_id,
          description: r.params["description"]&.strip,
          amount: amount,
          start_date: r.params["start_date"]&.strip,
          end_date: r.params["end_date"]&.strip,
          id: r.params["id"],
          participant_ids: participant_ids
        )
        handle_result(result, success_status: 201)
      end
    end

    # /api/expenses/:id routes
    r.on String do |id|
      find_result = Expense.find_result(id)
      unless find_result.success?
        error = find_result.failure
        response.status = error.http_status
        next error.to_api_hash
      end
      expense = find_result.value!

      event = Event.find(expense.event_id)
      unless event && member_of_workspace?(event.workspace_id)
        response.status = 403
        next { error: "Access denied" }
      end

      # PUT /api/expenses/:id - Update an expense (creator-only enforced in service)
      r.put do
        amount_param = r.params["amount"]
        amount = amount_param ? amount_param.to_f : nil

        participant_ids = r.params["participant_ids"]
        participant_ids = Array(participant_ids) if participant_ids

        result = Expenses::Update.call(
          expense_id: expense.id,
          current_user_id: user.id,
          workspace_id: event.workspace_id,
          description: r.params["description"]&.strip,
          amount: amount,
          start_date: r.params["start_date"]&.strip,
          end_date: r.params["end_date"]&.strip,
          participant_ids: participant_ids
        )
        handle_result(result)
      end

      # DELETE /api/expenses/:id - Delete an expense (creator-only enforced in service)
      r.delete do
        result = Expenses::Delete.call(
          expense_id: expense.id,
          current_user_id: user.id,
          workspace_id: event.workspace_id
        )
        handle_result(result)
      end
    end
  end
end
