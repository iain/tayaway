# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "events") do |r|
    response.status = 401
    next { error: "Authorization required" } unless current_user

    # GET /api/events - List all events
    r.is do
      r.get do
        events = Event.all_ordered
        pool = PoolSerializer.new
        pool.add_all(events, type: :event)

        response.status = 200
        { objects: pool.to_a }
      end

      # POST /api/events - Create a new event
      r.post do
        result = Events::Create.call(
          workspace_id: r.params["workspace_id"],
          user_id: current_user.id,
          name: r.params["name"]&.strip,
          description: r.params["description"]&.strip,
          date_ranges: r.params["date_ranges"] || []
        )
        handle_result(result, success_status: 201)
      end
    end

    # /api/events/:id routes
    r.on String do |id|
      event = Event.find(id)

      response.status = 404
      next { error: "Event not found" } unless event

      # GET /api/events/:id - Get event details (any authenticated user can view)
      r.is do
        r.get do
          pool = PoolSerializer.new
          pool.add_event(event)

          response.status = 200
          { objects: pool.to_a }
        end

        # PUT /api/events/:id - Update event (owner only)
        r.put do
          result = Events::Update.call(
            event_id: event.id,
            current_user_id: current_user.id,
            name: r.params["name"]&.strip,
            description: r.params["description"]&.strip,
            date_ranges: r.params["date_ranges"] || []
          )
          handle_result(result)
        end

        # DELETE /api/events/:id - Delete event (owner only)
        r.delete do
          result = Events::Delete.call(event_id: event.id, current_user_id: current_user.id)
          handle_result(result)
        end
      end

      # /api/events/:id/votes routes
      r.on "votes" do
        # GET /api/events/:id/votes - Get all votes for an event
        r.is do
          r.get do
            date_range_ids = DateRange.ids_for_event(event.id)
            votes = Vote.for_date_range_ids(date_range_ids)
            pool = PoolSerializer.new
            pool.add_all(votes, type: :vote)

            response.status = 200
            { objects: pool.to_a }
          end

          # POST /api/events/:id/votes - Create or update vote
          r.post do
            result = Votes::Upsert.call(
              event_id: event.id,
              user_id: current_user.id,
              date_range_id: r.params["date_range_id"],
              vote_response: r.params["response"],
              comment: r.params["comment"]&.strip,
              vote_id: r.params["id"]
            )

            result.either(
              ->(value) {
                vote = Vote.find(value[:vote_id])
                pool = PoolSerializer.new
                pool.add_vote(vote)

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
            result = Votes::Delete.call(event_id: event.id, vote_id: vote_id, user_id: current_user.id)
            handle_result(result)
          end
        end
      end
    end
  end
end
