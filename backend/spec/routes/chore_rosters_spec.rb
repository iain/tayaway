# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Chore rosters endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }
  let(:workspace) { TestFactories.workspace }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: e[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    DB[:events].where(id: e[:id]).first
  end

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe "POST /api/chore-rosters" do
    it "returns 401 without auth" do
      post "/api/chore-rosters"

      expect(last_response.status).to eq(401)
    end

    it "returns 400 when event_id is missing" do
      post "/api/chore-rosters",
           {}.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(400)
    end

    it "returns 403 when not a member of the event's workspace" do
      other_workspace = TestFactories.workspace
      other_event = TestFactories.event(workspace: other_workspace, user: user)

      post "/api/chore-rosters",
           { event_id: other_event[:id] }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end

    it "creates a chore roster" do
      post "/api/chore-rosters",
           { event_id: event[:id] }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      roster = body["objects"].find { |o| o["objectType"] == "choreRoster" }
      expect(roster).not_to be_nil
      expect(roster["eventId"]).to eq(event[:id])
    end
  end

  describe "GET /api/chore-rosters/:id" do
    it "returns 401 without auth" do
      roster = TestFactories.chore_roster(event: event, user: user)

      get "/api/chore-rosters/#{roster[:id]}"

      expect(last_response.status).to eq(401)
    end

    it "returns 404 for non-existent roster" do
      get "/api/chore-rosters/#{SecureRandom.uuid}", {}, auth_cookie

      expect(last_response.status).to eq(404)
    end

    it "returns 403 when not a member of the event's workspace" do
      other_workspace = TestFactories.workspace
      other_event = TestFactories.event(workspace: other_workspace, user: user)
      other_roster = TestFactories.chore_roster(event: other_event, user: user)

      get "/api/chore-rosters/#{other_roster[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(403)
    end

    it "returns the roster with chores and assignments" do
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster, name: "Dishes")
      TestFactories.chore_assignment(chore: chore, user: user, date: Date.today)

      get "/api/chore-rosters/#{roster[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["objects"].any? { |o| o["objectType"] == "choreRoster" }).to be true
      expect(body["objects"].any? { |o| o["objectType"] == "chore" && o["name"] == "Dishes" }).to be true
      expect(body["objects"].any? { |o| o["objectType"] == "choreAssignment" }).to be true
    end
  end

  describe "DELETE /api/chore-rosters/:id" do
    it "returns 401 without auth" do
      roster = TestFactories.chore_roster(event: event, user: user)

      delete "/api/chore-rosters/#{roster[:id]}"

      expect(last_response.status).to eq(401)
    end

    it "deletes the roster when user is the creator" do
      roster = TestFactories.chore_roster(event: event, user: user)

      delete "/api/chore-rosters/#{roster[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:chore_rosters].where(id: roster[:id]).count).to eq(0)
    end

    it "returns 403 when user is not the creator" do
      other_user = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: other_user)
      other_session = TestFactories.session(user: other_user)
      other_auth = { "HTTP_COOKIE" => "session_token=#{other_session[:token]}" }.merge(csrf_header)

      roster = TestFactories.chore_roster(event: event, user: user)

      delete "/api/chore-rosters/#{roster[:id]}", {}, other_auth

      expect(last_response.status).to eq(403)
    end

    it "deletes the roster when user is a workspace owner but not the creator or event owner" do
      creator = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: creator)
      roster = TestFactories.chore_roster(event: event, user: creator)

      owner_user = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: owner_user, role: "owner")
      owner_session = TestFactories.session(user: owner_user)
      owner_auth = { "HTTP_COOKIE" => "session_token=#{owner_session[:token]}" }.merge(csrf_header)

      delete "/api/chore-rosters/#{roster[:id]}", {}, owner_auth

      expect(last_response.status).to eq(200)
      expect(DB[:chore_rosters].where(id: roster[:id]).count).to eq(0)
    end
  end

  describe "POST /api/chore-rosters/:id/chores" do
    it "returns 401 without auth" do
      roster = TestFactories.chore_roster(event: event, user: user)

      post "/api/chore-rosters/#{roster[:id]}/chores"

      expect(last_response.status).to eq(401)
    end

    it "adds a chore to the roster" do
      roster = TestFactories.chore_roster(event: event, user: user)

      post "/api/chore-rosters/#{roster[:id]}/chores",
           { name: "Cooking", people_per_day: 2 }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      chore = body["objects"].find { |o| o["objectType"] == "chore" }
      expect(chore["name"]).to eq("Cooking")
    end

    it "stores an optional time" do
      roster = TestFactories.chore_roster(event: event, user: user)

      post "/api/chore-rosters/#{roster[:id]}/chores",
           { name: "Cooking", time: "18:30" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      chore = JSON.parse(last_response.body)["objects"].find { |o| o["objectType"] == "chore" }
      expect(chore["time"]).to eq("18:30")
    end
  end

  describe "PUT /api/chore-rosters/:id/chores/:cid" do
    it "updates a chore" do
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster, name: "Old Name")

      put "/api/chore-rosters/#{roster[:id]}/chores/#{chore[:id]}",
          { name: "New Name" }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      updated = body["objects"].find { |o| o["objectType"] == "chore" }
      expect(updated["name"]).to eq("New Name")
    end

    it "edits the time" do
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster, time: "18:00")

      put "/api/chore-rosters/#{roster[:id]}/chores/#{chore[:id]}",
          { time: "07:15" }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      updated = JSON.parse(last_response.body)["objects"].find { |o| o["objectType"] == "chore" }
      expect(updated["time"]).to eq("07:15")
    end

    it "clears the time when sent blank" do
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster, time: "18:00")

      put "/api/chore-rosters/#{roster[:id]}/chores/#{chore[:id]}",
          { time: "" }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      updated = JSON.parse(last_response.body)["objects"].find { |o| o["objectType"] == "chore" }
      expect(updated["time"]).to be_nil
    end

    it "leaves the time untouched when the key is omitted" do
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster, time: "18:00")

      put "/api/chore-rosters/#{roster[:id]}/chores/#{chore[:id]}",
          { name: "Renamed" }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      updated = JSON.parse(last_response.body)["objects"].find { |o| o["objectType"] == "chore" }
      expect(updated["time"]).to eq("18:00")
    end
  end

  describe "DELETE /api/chore-rosters/:id/chores/:cid" do
    it "deletes a chore" do
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster, name: "Cleaning")

      delete "/api/chore-rosters/#{roster[:id]}/chores/#{chore[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:chores].where(id: chore[:id]).count).to eq(0)
    end
  end

  describe "POST /api/chore-rosters/:id/assignments" do
    it "creates an assignment" do
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster)

      post "/api/chore-rosters/#{roster[:id]}/assignments",
           { chore_id: chore[:id], user_id: user[:id], date: Date.today.iso8601 }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      assignment = body["objects"].find { |o| o["objectType"] == "choreAssignment" }
      expect(assignment).not_to be_nil
    end
  end

  describe "PUT /api/chore-rosters/:id/assignments/:aid" do
    it "updates an assignment note" do
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster)
      assignment = TestFactories.chore_assignment(chore: chore, user: user, date: Date.today)

      put "/api/chore-rosters/#{roster[:id]}/assignments/#{assignment[:id]}",
          { note: "Bring gloves" }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      updated = body["objects"].find { |o| o["objectType"] == "choreAssignment" }
      expect(updated["note"]).to eq("Bring gloves")
    end
  end

  describe "DELETE /api/chore-rosters/:id/assignments/:aid" do
    it "deletes an assignment" do
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster)
      assignment = TestFactories.chore_assignment(chore: chore, user: user, date: Date.today)

      delete "/api/chore-rosters/#{roster[:id]}/assignments/#{assignment[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:chore_assignments].where(id: assignment[:id]).count).to eq(0)
    end
  end

  describe "POST /api/chore-rosters/:id/autofill" do
    it "returns 200 and runs autofill" do
      roster = TestFactories.chore_roster(event: event, user: user)
      TestFactories.chore(chore_roster: roster)

      # Add an attending RSVP so autofill has people to assign to
      now = Time.now
      DB[:rsvps].insert(id: SecureRandom.uuid, event_id: event[:id], user_id: user[:id],
                        attending: true, created_at: now, updated_at: now
      )

      post "/api/chore-rosters/#{roster[:id]}/autofill",
           {}.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
    end
  end

  describe "POST /api/chore-rosters/:id/clear-unpinned" do
    it "clears non-pinned assignments" do
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster)
      # Clearly-future dates: the service clears from "today" in the
      # *event's timezone*, while Date.today is the system zone (UTC on
      # CI) — a Date.today fixture lands in the service's past during the
      # nightly window where the event timezone is a day ahead of UTC.
      unpinned = TestFactories.chore_assignment(chore: chore, user: user, date: Date.today + 2, pinned: false)
      pinned = TestFactories.chore_assignment(chore: chore, user: user, date: Date.today + 3, pinned: true)

      post "/api/chore-rosters/#{roster[:id]}/clear-unpinned",
           {}.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      expect(DB[:chore_assignments].where(id: unpinned[:id]).count).to eq(0)
      expect(DB[:chore_assignments].where(id: pinned[:id]).count).to eq(1)
    end
  end
end
