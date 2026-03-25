# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Events endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }
  let(:workspace) { TestFactories.workspace }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe "GET /api/events" do
    it "returns 401 without auth" do
      get "/api/events"

      expect(last_response.status).to eq(401)
    end

    it "returns events for user's workspaces" do
      TestFactories.event(workspace: workspace, user: user, name: "Trip to Paris")

      get "/api/events", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      event = body["objects"].find { |o| o["objectType"] == "event" }
      expect(event["name"]).to eq("Trip to Paris")
    end

    it "does not return events from workspaces the user does not belong to" do
      other_workspace = TestFactories.workspace
      TestFactories.event(workspace: other_workspace, user: user, name: "Private Event")

      get "/api/events", {}, auth_cookie

      body = JSON.parse(last_response.body)
      names = body["objects"].select { |o| o["objectType"] == "event" }.map { |o| o["name"] }
      expect(names).not_to include("Private Event")
    end
  end

  describe "POST /api/events" do
    it "returns 401 without auth" do
      post "/api/events"

      expect(last_response.status).to eq(401)
    end

    it "returns 403 when not a member of the workspace" do
      other_workspace = TestFactories.workspace

      post "/api/events",
           { workspace_id: other_workspace[:id], name: "My Event" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end

    it "creates an event" do
      post "/api/events",
           { workspace_id: workspace[:id], name: "Beach Weekend" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      event = body["objects"].find { |o| o["objectType"] == "event" }
      expect(event["name"]).to eq("Beach Weekend")
      expect(event["workspaceId"]).to eq(workspace[:id])
    end

    it "returns 400 when name is missing" do
      post "/api/events",
           { workspace_id: workspace[:id] }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(400)
    end
  end

  describe "GET /api/events/:id" do
    it "returns 401 without auth" do
      event = TestFactories.event(workspace: workspace, user: user)

      get "/api/events/#{event[:id]}"

      expect(last_response.status).to eq(401)
    end

    it "returns 404 for non-existent event" do
      get "/api/events/#{SecureRandom.uuid}", {}, auth_cookie

      expect(last_response.status).to eq(404)
    end

    it "returns 403 when not a member of the event's workspace" do
      other_workspace = TestFactories.workspace
      other_event = TestFactories.event(workspace: other_workspace, user: user)

      get "/api/events/#{other_event[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(403)
    end

    it "returns event details" do
      event = TestFactories.event(workspace: workspace, user: user, name: "Ski Trip")

      get "/api/events/#{event[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      found = body["objects"].find { |o| o["objectType"] == "event" }
      expect(found["name"]).to eq("Ski Trip")
    end
  end

  describe "PUT /api/events/:id" do
    it "returns 401 without auth" do
      event = TestFactories.event(workspace: workspace, user: user)

      put "/api/events/#{event[:id]}"

      expect(last_response.status).to eq(401)
    end

    it "updates the event when user is the owner" do
      event = TestFactories.event(workspace: workspace, user: user, name: "Old Name")

      put "/api/events/#{event[:id]}",
          { name: "New Name" }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      updated = body["objects"].find { |o| o["objectType"] == "event" }
      expect(updated["name"]).to eq("New Name")
    end

    it "returns 403 when user is not the event owner" do
      other_user = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: other_user)
      other_session = TestFactories.session(user: other_user)
      other_auth = { "HTTP_COOKIE" => "session_token=#{other_session[:token]}" }.merge(csrf_header)

      event = TestFactories.event(workspace: workspace, user: user, name: "My Event")

      put "/api/events/#{event[:id]}",
          { name: "Hacked Name" }.to_json,
          other_auth.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end
  end

  describe "DELETE /api/events/:id" do
    it "returns 401 without auth" do
      event = TestFactories.event(workspace: workspace, user: user)

      delete "/api/events/#{event[:id]}"

      expect(last_response.status).to eq(401)
    end

    it "deletes the event when user is the owner" do
      event = TestFactories.event(workspace: workspace, user: user)

      delete "/api/events/#{event[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:events].where(id: event[:id]).count).to eq(0)
    end

    it "returns 403 when user is not the event owner" do
      other_user = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: other_user)
      other_session = TestFactories.session(user: other_user)
      other_auth = { "HTTP_COOKIE" => "session_token=#{other_session[:token]}" }.merge(csrf_header)

      event = TestFactories.event(workspace: workspace, user: user)

      delete "/api/events/#{event[:id]}", {}, other_auth

      expect(last_response.status).to eq(403)
    end
  end

  describe "POST /api/events/:id/poll" do
    it "returns 401 without auth" do
      event = TestFactories.event(workspace: workspace, user: user)

      post "/api/events/#{event[:id]}/poll"

      expect(last_response.status).to eq(401)
    end

    it "creates a date poll" do
      event = TestFactories.event(workspace: workspace, user: user)
      deadline = (Date.today + 7).iso8601

      post "/api/events/#{event[:id]}/poll",
           { deadline: deadline }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      poll = body["objects"].find { |o| o["objectType"] == "datePoll" }
      expect(poll).not_to be_nil
      expect(poll["eventId"]).to eq(event[:id])
    end
  end

  describe "POST /api/events/:id/poll/date-ranges" do
    it "adds a date range to an open poll" do
      event = TestFactories.event(workspace: workspace, user: user)
      TestFactories.date_poll(event: event)

      post "/api/events/#{event[:id]}/poll/date-ranges",
           { start_date: "2026-07-01", end_date: "2026-07-07" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      dr = body["objects"].find { |o| o["objectType"] == "dateRange" }
      expect(dr).not_to be_nil
    end
  end

  describe "DELETE /api/events/:id/poll/date-ranges/:dr_id" do
    it "removes a date range from an open poll" do
      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      dr = TestFactories.date_range(date_poll: poll)

      delete "/api/events/#{event[:id]}/poll/date-ranges/#{dr[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:date_ranges].where(id: dr[:id]).count).to eq(0)
    end
  end

  describe "POST /api/events/:id/poll/close" do
    it "closes a poll with a selected date range" do
      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      dr = TestFactories.date_range(date_poll: poll)

      post "/api/events/#{event[:id]}/poll/close",
           { selected_date_range_id: dr[:id] }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      updated_poll = body["objects"].find { |o| o["objectType"] == "datePoll" }
      expect(updated_poll["selectedDateRangeId"]).to eq(dr[:id])
    end

    it "returns 403 when user is not the event owner" do
      other_user = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: other_user)
      other_session = TestFactories.session(user: other_user)
      other_auth = { "HTTP_COOKIE" => "session_token=#{other_session[:token]}" }.merge(csrf_header)

      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      dr = TestFactories.date_range(date_poll: poll)

      post "/api/events/#{event[:id]}/poll/close",
           { selected_date_range_id: dr[:id] }.to_json,
           other_auth.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end
  end

  describe "POST /api/events/:id/poll/reopen" do
    it "reopens a resolved poll" do
      event = TestFactories.event(workspace: workspace, user: user)
      dr = nil

      DB.transaction do
        poll = TestFactories.date_poll(event: event)
        dr = TestFactories.date_range(date_poll: poll)
        DB[:date_polls].where(id: poll[:id]).update(
          selected_date_range_id: dr[:id],
          closed_at: Time.now
        )
      end

      new_deadline = (Date.today + 14).iso8601

      post "/api/events/#{event[:id]}/poll/reopen",
           { deadline: new_deadline }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      updated_poll = body["objects"].find { |o| o["objectType"] == "datePoll" }
      expect(updated_poll["closedAt"]).to be_nil
      expect(updated_poll["selectedDateRangeId"]).to be_nil
    end
  end

  describe "GET /api/events/:id/votes" do
    it "returns 401 without auth" do
      event = TestFactories.event(workspace: workspace, user: user)

      get "/api/events/#{event[:id]}/votes"

      expect(last_response.status).to eq(401)
    end

    it "returns votes for an event" do
      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      dr = TestFactories.date_range(date_poll: poll)
      TestFactories.vote(date_range: dr, user: user, response: "yes")

      get "/api/events/#{event[:id]}/votes", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      vote = body["objects"].find { |o| o["objectType"] == "vote" }
      expect(vote["response"]).to eq("yes")
    end

    it "returns empty objects when there is no poll" do
      event = TestFactories.event(workspace: workspace, user: user)

      get "/api/events/#{event[:id]}/votes", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      votes = body["objects"].select { |o| o["objectType"] == "vote" }
      expect(votes).to be_empty
    end
  end

  describe "POST /api/events/:id/votes" do
    it "creates a vote" do
      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      dr = TestFactories.date_range(date_poll: poll)

      post "/api/events/#{event[:id]}/votes",
           { date_range_id: dr[:id], response: "yes" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      vote = body["objects"].find { |o| o["objectType"] == "vote" }
      expect(vote["response"]).to eq("yes")
    end
  end

  describe "DELETE /api/events/:id/votes/:vote_id" do
    it "deletes a vote" do
      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      dr = TestFactories.date_range(date_poll: poll)
      vote = TestFactories.vote(date_range: dr, user: user)

      delete "/api/events/#{event[:id]}/votes/#{vote[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:votes].where(id: vote[:id]).count).to eq(0)
    end
  end

  describe "GET /api/events/:id/rsvps" do
    it "returns 401 without auth" do
      event = TestFactories.event(workspace: workspace, user: user)

      get "/api/events/#{event[:id]}/rsvps"

      expect(last_response.status).to eq(401)
    end

    it "returns RSVPs for an event" do
      event = TestFactories.event(workspace: workspace, user: user)
      TestFactories.rsvp(event: event, user: user, attending: true)

      get "/api/events/#{event[:id]}/rsvps", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      rsvp = body["objects"].find { |o| o["objectType"] == "rsvp" }
      expect(rsvp["attending"]).to be true
    end
  end

  describe "POST /api/events/:id/rsvps" do
    it "creates an RSVP" do
      # RSVPs require the event to have dates set
      event = TestFactories.event(workspace: workspace, user: user)
      DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

      post "/api/events/#{event[:id]}/rsvps",
           { attending: true }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      rsvp = body["objects"].find { |o| o["objectType"] == "rsvp" }
      expect(rsvp["attending"]).to be true
    end

    it "updates an existing RSVP" do
      # RSVPs require the event to have dates set
      event = TestFactories.event(workspace: workspace, user: user)
      DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
      TestFactories.rsvp(event: event, user: user, attending: true)

      # Upserting without an id uses the existing RSVP for the user
      post "/api/events/#{event[:id]}/rsvps",
           { attending: false }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      updated = body["objects"].find { |o| o["objectType"] == "rsvp" }
      expect(updated["attending"]).to be false
    end
  end

  describe "DELETE /api/events/:id/rsvps/:rsvp_id" do
    it "deletes an RSVP" do
      event = TestFactories.event(workspace: workspace, user: user)
      rsvp = TestFactories.rsvp(event: event, user: user)

      delete "/api/events/#{event[:id]}/rsvps/#{rsvp[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:rsvps].where(id: rsvp[:id]).count).to eq(0)
    end
  end
end
