# typed: true
# frozen_string_literal: true

class App
  hash_branch("api", "events") do |r|
    response.status = 401
    next { error: "Authorization required" } unless current_user

    # GET /api/events - List all events
    r.is do
      r.get do
        response.status = 200
        { events: Event.order(:created_at).all.map(&:to_api_hash) }
      end

      # POST /api/events - Create a new event
      r.post do
        name = r.params["name"]&.strip
        description = r.params["description"]&.strip
        date_ranges_params = r.params["date_ranges"] || []

        response.status = 400
        next { error: "Name is required" } if name.nil? || name.empty?

        DB.transaction do
          event = Event.create(
            user_id: current_user.id,
            name: name,
            description: description&.empty? ? nil : description
          )

          date_ranges_params.each do |dr|
            DateRange.create(
              event_id: event.id,
              start_date: Date.parse(dr["start_date"]),
              end_date: Date.parse(dr["end_date"])
            )
          end

          response.status = 201
          { event: event.reload.to_api_hash }
        end
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
          response.status = 200
          { event: event.to_api_hash }
        end

        # PUT /api/events/:id - Update event (owner only)
        r.put do
          response.status = 403
          next { error: "Access denied" } unless event.user_id == current_user.id

          name = r.params["name"]&.strip
          description = r.params["description"]&.strip
          date_ranges_params = r.params["date_ranges"] || []

          response.status = 400
          next { error: "Name is required" } if name.nil? || name.empty?

          DB.transaction do
            event.update(
              name: name,
              description: description&.empty? ? nil : description
            )

            # Replace all date ranges
            event.date_ranges_dataset.delete

            date_ranges_params.each do |dr|
              DateRange.create(
                event_id: event.id,
                start_date: Date.parse(dr["start_date"]),
                end_date: Date.parse(dr["end_date"])
              )
            end

            response.status = 200
            { event: event.reload.to_api_hash }
          end
        end

        # DELETE /api/events/:id - Delete event (owner only)
        r.delete do
          response.status = 403
          next { error: "Access denied" } unless event.user_id == current_user.id

          event.destroy
          response.status = 200
          { message: "Event deleted successfully" }
        end
      end

      # /api/events/:id/votes routes
      r.on "votes" do
        # GET /api/events/:id/votes - Get all votes for an event
        r.is do
          r.get do
            votes = Vote.where(date_range_id: event.date_ranges.map(&:id)).all
            response.status = 200
            { votes: votes.map(&:to_api_hash) }
          end

          # POST /api/events/:id/votes - Create or update vote
          r.post do
            date_range_id = r.params["date_range_id"]
            vote_response = r.params["response"]
            comment = r.params["comment"]&.strip

            response.status = 400
            next { error: "date_range_id is required" } if date_range_id.nil? || date_range_id.empty?
            next { error: "response is required" } if vote_response.nil? || vote_response.empty?
            next { error: "Invalid response value" } unless Vote::VALID_RESPONSES.include?(vote_response)

            date_range = DateRange.first(id: date_range_id)
            next { error: "Date range not found" } unless date_range
            next { error: "Date range does not belong to this event" } unless date_range.event_id == event.id

            existing_vote = Vote.first(date_range_id: date_range_id, user_id: current_user.id)

            if existing_vote
              existing_vote.update(
                response: vote_response,
                comment: comment&.empty? ? nil : comment
              )
              response.status = 200
              { vote: existing_vote.to_api_hash }
            else
              vote = Vote.create(
                date_range_id: date_range_id,
                user_id: current_user.id,
                response: vote_response,
                comment: comment&.empty? ? nil : comment
              )
              response.status = 201
              { vote: vote.to_api_hash }
            end
          end
        end

        # DELETE /api/events/:id/votes/:vote_id - Remove vote
        r.on String do |vote_id|
          r.delete do
            vote = Vote.first(id: vote_id)

            response.status = 404
            next { error: "Vote not found" } unless vote

            response.status = 403
            next { error: "Access denied" } unless vote.user_id == current_user.id

            # Verify vote belongs to this event
            date_range = vote.date_range
            response.status = 400
            next { error: "Vote does not belong to this event" } unless date_range&.event_id == event.id

            vote.destroy
            response.status = 200
            { message: "Vote deleted successfully" }
          end
        end
      end
    end
  end
end
