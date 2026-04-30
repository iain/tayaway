# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Settlements endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }
  let(:workspace) { TestFactories.workspace }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  define_method(:create_event_with_expense_and_rsvp) do
    event = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: event[:id]).update(
      start_date: Date.today,
      end_date: Date.today + 7
    )
    event = DB[:events].where(id: event[:id]).first

    other_user = TestFactories.user
    TestFactories.workspace_membership(workspace: workspace, user: other_user)

    # Both users RSVP as attending
    now = Time.now
    DB[:rsvps].insert(id: SecureRandom.uuid, event_id: event[:id], user_id: user[:id],
                      attending: true, created_at: now, updated_at: now
    )
    DB[:rsvps].insert(id: SecureRandom.uuid, event_id: event[:id], user_id: other_user[:id],
                      attending: true, created_at: now, updated_at: now
    )

    # user paid an expense
    expense_id = SecureRandom.uuid
    DB[:expenses].insert(
      id: expense_id,
      event_id: event[:id],
      user_id: user[:id],
      amount: 100.0,
      description: "Dinner",
      start_date: Date.today,
      end_date: Date.today + 7,
      created_at: now,
      updated_at: now
    )

    { event: event, expense_id: expense_id, other_user: other_user }
  end

  describe "GET /api/settlements" do
    it "returns 401 without auth" do
      get "/api/settlements"

      expect(last_response.status).to eq(401)
    end

    it "returns 400 when event_id is missing" do
      get "/api/settlements", {}, auth_cookie

      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("event_id is required")
    end

    it "returns 403 when not a member of the event's workspace" do
      other_workspace = TestFactories.workspace
      other_event = TestFactories.event(workspace: other_workspace, user: user)

      get "/api/settlements?event_id=#{other_event[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(403)
    end

    it "returns settlements for an event" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      settlement_id = SecureRandom.uuid
      DB[:settlements].insert(id: settlement_id, event_id: event[:id], user_id: user[:id],
                              created_at: now, updated_at: now
      )

      get "/api/settlements?event_id=#{event[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      settlement = body["objects"].find { |o| o["objectType"] == "settlement" }
      expect(settlement["id"]).to eq(settlement_id)
    end
  end

  describe "POST /api/settlements" do
    it "returns 401 without auth" do
      post "/api/settlements"

      expect(last_response.status).to eq(401)
    end

    it "returns 400 when event_id is missing" do
      post "/api/settlements", {}.to_json, auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(400)
    end

    it "returns 403 when not a member of the event's workspace" do
      other_workspace = TestFactories.workspace
      other_event = TestFactories.event(workspace: other_workspace, user: user)

      post "/api/settlements",
           { event_id: other_event[:id] }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end

    it "creates a settlement when the event has expenses and attending RSVPs" do
      data = create_event_with_expense_and_rsvp
      event = data[:event]

      post "/api/settlements",
           { event_id: event[:id] }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      settlement = body["objects"].find { |o| o["objectType"] == "settlement" }
      expect(settlement).not_to be_nil
      expect(settlement["eventId"]).to eq(event[:id])
    end
  end

  describe "DELETE /api/settlements/:id" do
    it "returns 401 without auth" do
      delete "/api/settlements/#{SecureRandom.uuid}"

      expect(last_response.status).to eq(401)
    end

    it "returns 404 for non-existent settlement" do
      delete "/api/settlements/#{SecureRandom.uuid}", {}, auth_headers

      expect(last_response.status).to eq(404)
    end

    it "deletes a settlement when user is the creator" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      settlement_id = SecureRandom.uuid
      DB[:settlements].insert(id: settlement_id, event_id: event[:id], user_id: user[:id],
                              created_at: now, updated_at: now
      )

      delete "/api/settlements/#{settlement_id}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:settlements].where(id: settlement_id).count).to eq(0)
    end

    it "returns 403 when user is not the creator or event owner" do
      event = TestFactories.event(workspace: workspace, user: user)
      other_user = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: other_user)
      other_session = TestFactories.session(user: other_user)
      other_auth = { "HTTP_COOKIE" => "session_token=#{other_session[:token]}" }.merge(csrf_header)

      now = Time.now
      settlement_id = SecureRandom.uuid
      DB[:settlements].insert(id: settlement_id, event_id: event[:id], user_id: user[:id],
                              created_at: now, updated_at: now
      )

      delete "/api/settlements/#{settlement_id}", {}, other_auth

      expect(last_response.status).to eq(403)
    end
  end

  describe "PUT /api/settlements/transfers/:id" do
    it "returns 401 without auth" do
      put "/api/settlements/transfers/#{SecureRandom.uuid}"

      expect(last_response.status).to eq(401)
    end

    it "returns 404 for non-existent transfer" do
      put "/api/settlements/transfers/#{SecureRandom.uuid}",
          { paid: true }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(404)
    end

    it "allows the recipient to mark a transfer as paid" do
      event = TestFactories.event(workspace: workspace, user: user)
      DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
      now = Time.now
      settlement_id = SecureRandom.uuid
      DB[:settlements].insert(id: settlement_id, event_id: event[:id], user_id: user[:id],
                              created_at: now, updated_at: now
      )

      other_user = TestFactories.user
      transfer_id = SecureRandom.uuid
      DB[:settlement_transfers].insert(
        id: transfer_id,
        settlement_id: settlement_id,
        from_user_id: other_user[:id],
        to_user_id: user[:id],
        amount: 50.0,
        created_at: now,
        updated_at: now
      )

      put "/api/settlements/transfers/#{transfer_id}",
          { paid: true }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      transfer = DB[:settlement_transfers].where(id: transfer_id).first
      expect(transfer[:paid_at]).not_to be_nil
    end

    it "returns 403 when caller is neither sender nor recipient" do
      event = TestFactories.event(workspace: workspace, user: user)
      DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
      now = Time.now
      settlement_id = SecureRandom.uuid
      DB[:settlements].insert(id: settlement_id, event_id: event[:id], user_id: user[:id],
                              created_at: now, updated_at: now
      )

      # Two users on the workspace who are the actual pair; the logged-in
      # `user` (the request actor) is neither.
      sender = TestFactories.user
      recipient = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: sender)
      TestFactories.workspace_membership(workspace: workspace, user: recipient)

      transfer_id = SecureRandom.uuid
      DB[:settlement_transfers].insert(
        id: transfer_id,
        settlement_id: settlement_id,
        from_user_id: sender[:id],
        to_user_id: recipient[:id],
        amount: 50.0,
        created_at: now,
        updated_at: now
      )

      put "/api/settlements/transfers/#{transfer_id}",
          { paid: true }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end
  end
end
