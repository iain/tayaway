# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  hash_branch("api", "events") do |r|
    user = require_auth

    # GET /api/events - List events in user's workspaces
    r.is do
      r.get do
        workspaces = Workspace.for_user(user.id)
        workspace_ids = workspaces.map(&:id)
        events = Event.for_workspace_ids(workspace_ids)

        # Group events by workspace for correct member resolution
        all_objects = []
        events.group_by(&:workspace_id).each do |ws_id, ws_events|
          membership = WorkspaceMembership.find_by_workspace_and_user(ws_id, user.id)
          pool = PoolSerializer.new(membership: membership)
          pool.add(:event, ws_events)
          all_objects.concat(pool.to_a)
        end

        response.status = 200
        { objects: all_objects }
      end

      # POST /api/events - Create a new event
      r.post do
        # Use provided workspace_id or get user's first workspace
        workspace_id = r.params["workspace_id"]
        unless workspace_id
          first_workspace = Workspace.for_user(user.id).first
          workspace_id = first_workspace&.id
        end

        unless workspace_id
          response.status = 400
          next { error: "No workspace available. Please create a workspace first." }
        end

        # Verify user is a member of the target workspace
        unless member_of_workspace?(workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        result = Events::Create.call(
          workspace_id: workspace_id,
          membership: current_membership,
          name: r.params["name"]&.strip,
          description: r.params["description"]&.strip,
          id: r.params["id"],
          start_date: r.params["start_date"]&.strip,
          end_date: r.params["end_date"]&.strip,
          location_name: r.params["location_name"]&.strip,
          latitude: ValidationLimits.parse_coordinate(r.params["latitude"]),
          longitude: ValidationLimits.parse_coordinate(r.params["longitude"]),
          timezone: r.params["timezone"]&.strip
        )
        handle_result(result, success_status: 201)
      end
    end

    # /api/events/:id routes
    r.on String do |id|
      find_result = Event.find_result(id)
      unless find_result.success?
        error = find_result.failure
        response.status = error.http_status
        next error.to_api_hash
      end
      event = find_result.value!

      # Verify user is a member of the event's workspace
      response.status = 403
      next { error: "Access denied" } unless member_of_workspace?(event.workspace_id)

      # GET /api/events/:id - Get event details (any authenticated user can view)
      r.is do
        r.get do
          pool = PoolSerializer.new(membership: current_membership)
          pool.add(:event, [event])

          response.status = 200
          { objects: pool.to_a }
        end

        # PUT /api/events/:id - Update event (owner only)
        r.put do
          result = Events::Update.call(
            event_id: event.id,
            membership: current_membership,
            name: r.params["name"]&.strip,
            description: r.params["description"]&.strip,
            start_date: r.params["start_date"]&.strip,
            end_date: r.params["end_date"]&.strip,
            location_name: r.params["location_name"]&.strip,
            latitude: ValidationLimits.parse_coordinate(r.params["latitude"]),
            longitude: ValidationLimits.parse_coordinate(r.params["longitude"]),
            timezone: r.params["timezone"]&.strip
          )
          handle_result(result)
        end

        # DELETE /api/events/:id - Delete event (owner only)
        r.delete do
          result = Events::Delete.call(event_id: event.id, membership: current_membership)
          handle_result(result)
        end
      end

      # /api/events/:id/poll routes
      r.on "poll" do
        # POST /api/events/:id/poll - Create a date poll
        r.is do
          r.post do
            result = DatePolls::Create.call(
              event_id: event.id,
              membership: current_membership,
              deadline: r.params["deadline"]
            )
            handle_result(result, success_status: 201)
          end
        end

        # POST /api/events/:id/poll/close - Close poll with winner
        r.on "close" do
          r.post do
            result = DatePolls::Close.call(
              event_id: event.id,
              membership: current_membership,
              selected_date_range_id: r.params["selected_date_range_id"]
            )
            handle_result(result)
          end
        end

        # POST /api/events/:id/poll/reopen - Reopen a resolved poll
        r.on "reopen" do
          r.post do
            result = DatePolls::Reopen.call(
              event_id: event.id,
              membership: current_membership,
              deadline: r.params["deadline"]
            )
            handle_result(result)
          end
        end

        # /api/events/:id/poll/date-ranges routes
        r.on "date-ranges" do
          # POST /api/events/:id/poll/date-ranges - Add a date range
          r.is do
            r.post do
              result = DatePolls::AddDateRange.call(
                event_id: event.id,
                membership: current_membership,
                start_date: r.params["start_date"],
                end_date: r.params["end_date"],
                id: r.params["id"]
              )
              handle_result(result, success_status: 201)
            end
          end

          # DELETE /api/events/:id/poll/date-ranges/:dr_id - Remove a date range
          r.on String do |dr_id|
            r.delete do
              result = DatePolls::RemoveDateRange.call(
                event_id: event.id,
                membership: current_membership,
                date_range_id: dr_id
              )
              handle_result(result)
            end
          end
        end
      end

      # /api/events/:id/rsvps routes
      r.on "rsvps" do
        # GET /api/events/:id/rsvps - Get all RSVPs for an event
        r.is do
          r.get do
            rsvps = Rsvp.for_event(event.id)
            pool = PoolSerializer.new(membership: current_membership)
            pool.add(:rsvp, rsvps)

            response.status = 200
            { objects: pool.to_a }
          end

          # POST /api/events/:id/rsvps - Create or update RSVP
          r.post do
            result = Rsvps::Upsert.call(
              event_id: event.id,
              membership: current_membership,
              user_id: r.params["user_id"] || current_membership.user_id,
              attending: r.params["attending"],
              attendance: r.params["attendance"],
              start_date: r.params["start_date"]&.strip,
              end_date: r.params["end_date"]&.strip,
              rsvp_id: r.params["id"]
            )

            result.either(
              ->(value) {
                rsvp = Rsvp.find(value[:rsvp_id])
                pool = PoolSerializer.new(membership: current_membership)
                pool.add(:rsvp, [rsvp])

                response.status = value[:created] ? 201 : 200
                { objects: pool.to_a }
              },
              ->(error) {
                response.status = error.http_status
                error.to_api_hash
              }
            )
          end
        end

        # DELETE /api/events/:id/rsvps/:rsvp_id - Remove RSVP
        r.on String do |rsvp_id|
          r.delete do
            result = Rsvps::Delete.call(event_id: event.id, rsvp_id: rsvp_id, membership: current_membership)
            handle_result(result)
          end
        end
      end

      # /api/events/:id/votes routes
      r.on "votes" do
        # GET /api/events/:id/votes - Get all votes for an event
        r.is do
          r.get do
            poll = DatePoll.find_by_event(event.id)
            date_range_ids = poll ? DateRange.ids_for_date_poll(poll.id) : []
            votes = Vote.for_date_range_ids(date_range_ids)
            pool = PoolSerializer.new(membership: current_membership)
            pool.add(:vote, votes)

            response.status = 200
            { objects: pool.to_a }
          end

          # POST /api/events/:id/votes - Create or update vote
          r.post do
            result = Votes::Upsert.call(
              event_id: event.id,
              membership: current_membership,
              date_range_id: r.params["date_range_id"],
              vote_response: r.params["response"],
              comment: r.params["comment"]&.strip,
              vote_id: r.params["id"]
            )

            result.either(
              ->(value) {
                vote = Vote.find(value[:vote_id])
                pool = PoolSerializer.new(membership: current_membership)
                pool.add(:vote, [vote])

                response.status = value[:created] ? 201 : 200
                { objects: pool.to_a }
              },
              ->(error) {
                response.status = error.http_status
                error.to_api_hash
              }
            )
          end
        end

        # DELETE /api/events/:id/votes/:vote_id - Remove vote
        r.on String do |vote_id|
          r.delete do
            result = Votes::Delete.call(event_id: event.id, vote_id: vote_id, membership: current_membership)
            handle_result(result)
          end
        end
      end
    end
  end
end
