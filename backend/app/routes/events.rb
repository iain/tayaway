# typed: true
# frozen_string_literal: true

class App
  hash_branch("api", "events") do |r|
    response.status = 401
    next { error: "Authorization required" } unless current_user

    # GET /api/events - List all events
    r.is do
      r.get do
        events = Event.order(:created_at).all
        pool = PoolSerializer.new
        pool.add_all(events)

        response.status = 200
        { objects: pool.to_a }
      end

      # POST /api/events - Create a new event
      r.post do
        result = Events::Create.call(
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
      event = Event.first(id: id)

      response.status = 404
      next { error: "Event not found" } unless event

      # GET /api/events/:id - Get event details (any authenticated user can view)
      r.is do
        r.get do
          pool = PoolSerializer.new
          pool.add(event)

          response.status = 200
          { objects: pool.to_a }
        end

        # PUT /api/events/:id - Update event (owner only)
        r.put do
          result = Events::Update.call(
            event: event,
            current_user_id: current_user.id,
            name: r.params["name"]&.strip,
            description: r.params["description"]&.strip,
            date_ranges: r.params["date_ranges"] || []
          )
          handle_result(result)
        end

        # DELETE /api/events/:id - Delete event (owner only)
        r.delete do
          result = Events::Delete.call(event: event, current_user_id: current_user.id)
          handle_result(result)
        end
      end

      # /api/events/:id/votes routes
      r.on "votes" do
        # GET /api/events/:id/votes - Get all votes for an event
        r.is do
          r.get do
            votes = Vote.where(date_range_id: event.date_ranges.map(&:id)).all
            pool = PoolSerializer.new
            pool.add_all(votes)

            response.status = 200
            { objects: pool.to_a }
          end

          # POST /api/events/:id/votes - Create or update vote
          r.post do
            result = Votes::Upsert.call(
              event: event,
              user_id: current_user.id,
              date_range_id: r.params["date_range_id"],
              vote_response: r.params["response"],
              comment: r.params["comment"]&.strip,
              vote_id: r.params["id"]
            )

            result.either(
              ->(value) {
                vote = Vote.first(id: value[:vote][:id])
                pool = PoolSerializer.new
                pool.add(vote)

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
            result = Votes::Delete.call(event: event, vote_id: vote_id, user_id: current_user.id)
            handle_result(result)
          end
        end
      end
    end
  end
end
