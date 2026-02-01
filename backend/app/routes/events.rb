# typed: true
# frozen_string_literal: true

class App
  hash_branch "api/events" do |r|
      response.status = 401
      next { error: "Authorization required" } unless current_user

      # GET /api/events - List current user's events
      r.is do
        r.get do
          response.status = 200
          { events: current_user.events.map(&:to_api_hash) }
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

        response.status = 403
        next { error: "Access denied" } unless event.user_id == current_user.id

        # GET /api/events/:id - Get event details
        r.get do
          response.status = 200
          { event: event.to_api_hash }
        end

        # PUT /api/events/:id - Update event
        r.put do
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

        # DELETE /api/events/:id - Delete event
        r.delete do
          event.destroy
          response.status = 200
          { message: "Event deleted successfully" }
        end
      end
  end
end
