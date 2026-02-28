# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "chore-rosters") do |r|
    user = require_auth

    # POST /api/chore-rosters - Create a chore roster
    r.is do
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

        result = ChoreRosters::Create.call(
          event_id: event_id,
          user_id: user.id,
          workspace_id: event.workspace_id,
          id: r.params["id"]
        )
        handle_result(result, success_status: 201)
      end
    end

    # /api/chore-rosters/:id/...
    r.on String do |id|
      find_result = ChoreRoster.find_result(id)
      unless find_result.success?
        error = find_result.failure
        response.status = error.http_status
        next error.to_api_hash
      end
      roster = find_result.value!

      event = Event.find(roster.event_id)
      unless event && member_of_workspace?(event.workspace_id)
        response.status = 403
        next { error: "Access denied" }
      end

      workspace_id = event.workspace_id

      # POST /api/chore-rosters/:id/autofill
      r.on "autofill" do
        r.post do
          result = ChoreRosters::Autofill.call(
            roster_id: roster.id,
            workspace_id: workspace_id
          )
          handle_result(result)
        end
      end

      # /api/chore-rosters/:id/assignments
      r.on "assignments" do
        # /api/chore-rosters/:id/assignments/:aid
        r.on String do |aid|
          # PUT /api/chore-rosters/:id/assignments/:aid
          r.put do
            result = ChoreRosters::UpdateAssignment.call(
              assignment_id: aid,
              workspace_id: workspace_id,
              note: r.params["note"],
              user_id: r.params["user_id"]
            )
            handle_result(result)
          end

          # DELETE /api/chore-rosters/:id/assignments/:aid
          r.delete do
            result = ChoreRosters::DeleteAssignment.call(
              assignment_id: aid,
              workspace_id: workspace_id
            )
            handle_result(result)
          end
        end

        # POST /api/chore-rosters/:id/assignments
        r.post do
          result = ChoreRosters::CreateAssignment.call(
            roster_id: roster.id,
            workspace_id: workspace_id,
            chore_id: r.params["chore_id"],
            user_id: r.params["user_id"],
            date: r.params["date"],
            note: r.params["note"],
            id: r.params["id"]
          )
          handle_result(result, success_status: 201)
        end
      end

      # /api/chore-rosters/:id/chores
      r.on "chores" do
        # /api/chore-rosters/:id/chores/:cid
        r.on String do |cid|
          # PUT /api/chore-rosters/:id/chores/:cid
          r.put do
            ppd_param = r.params["people_per_day"]
            ppd = ppd_param ? ppd_param.to_i : nil
            pos_param = r.params["position"]
            pos = pos_param ? pos_param.to_f : nil

            result = ChoreRosters::UpdateChore.call(
              chore_id: cid,
              workspace_id: workspace_id,
              name: r.params["name"]&.strip,
              people_per_day: ppd,
              position: pos
            )
            handle_result(result)
          end

          # DELETE /api/chore-rosters/:id/chores/:cid
          r.delete do
            result = ChoreRosters::DeleteChore.call(
              chore_id: cid,
              roster_id: roster.id,
              workspace_id: workspace_id
            )
            handle_result(result)
          end
        end

        # POST /api/chore-rosters/:id/chores
        r.post do
          ppd_param = r.params["people_per_day"]
          ppd = ppd_param ? ppd_param.to_i : nil

          result = ChoreRosters::AddChore.call(
            roster_id: roster.id,
            workspace_id: workspace_id,
            name: r.params["name"]&.strip,
            people_per_day: ppd,
            id: r.params["id"]
          )
          handle_result(result, success_status: 201)
        end
      end

      # DELETE /api/chore-rosters/:id
      r.delete do
        result = ChoreRosters::DeleteRoster.call(
          roster_id: roster.id,
          current_user_id: user.id,
          workspace_id: workspace_id
        )
        handle_result(result)
      end

      # GET /api/chore-rosters/:id - Get roster with all chores and assignments
      r.get do
        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_chore_roster(roster)

        response.status = 200
        { objects: pool.to_a }
      end
    end
  end
end
