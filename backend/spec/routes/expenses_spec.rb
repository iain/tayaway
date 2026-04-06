# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Expenses endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }
  let(:workspace) { TestFactories.workspace }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  define_method(:create_expense) do |event:, user:, amount: 50.0, description: "Test expense"|
    now = Time.now
    expense_id = SecureRandom.uuid
    DB[:expenses].insert(
      id: expense_id,
      event_id: event[:id],
      user_id: user[:id],
      amount: amount,
      description: description,
      start_date: Date.today,
      end_date: Date.today + 3,
      created_at: now,
      updated_at: now
    )
    DB[:expenses].where(id: expense_id).first
  end

  describe "GET /api/expenses" do
    it "returns 401 without auth" do
      get "/api/expenses"

      expect(last_response.status).to eq(401)
    end

    it "returns 400 when event_id is missing" do
      get "/api/expenses", {}, auth_cookie

      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("event_id is required")
    end

    it "returns 403 when not a member of the event's workspace" do
      other_workspace = TestFactories.workspace
      other_event = TestFactories.event(workspace: other_workspace, user: user)

      get "/api/expenses?event_id=#{other_event[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(403)
    end

    it "returns expenses for an event" do
      create_expense(event: event, user: user, description: "Hotel")

      get "/api/expenses?event_id=#{event[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expense = body["objects"].find { |o| o["objectType"] == "expense" }
      expect(expense["description"]).to eq("Hotel")
    end
  end

  describe "POST /api/expenses" do
    it "returns 401 without auth" do
      post "/api/expenses"

      expect(last_response.status).to eq(401)
    end

    it "returns 400 when event_id is missing" do
      post "/api/expenses",
           { description: "Food", amount: 30.0, start_date: Date.today.iso8601, end_date: Date.today.iso8601 }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(400)
    end

    it "returns 403 when not a member of the event's workspace" do
      other_workspace = TestFactories.workspace
      other_event = TestFactories.event(workspace: other_workspace, user: user)

      post "/api/expenses",
           { event_id: other_event[:id], description: "Food", amount: 30.0,
             start_date: Date.today.iso8601, end_date: Date.today.iso8601 }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end

    it "creates an expense" do
      # Expense creation requires an attending RSVP
      now = Time.now
      DB[:rsvps].insert(id: SecureRandom.uuid, event_id: event[:id], user_id: user[:id],
                        attending: true, created_at: now, updated_at: now
      )

      post "/api/expenses",
           { event_id: event[:id], description: "Groceries", amount: 75.50,
             start_date: Date.today.iso8601, end_date: (Date.today + 2).iso8601 }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      expense = body["objects"].find { |o| o["objectType"] == "expense" }
      expect(expense["description"]).to eq("Groceries")
      expect(expense["amount"]).to eq(75.50)
      expect(expense["userId"]).to eq(user[:id])
    end

    it "returns 400 when description is missing" do
      post "/api/expenses",
           { event_id: event[:id], amount: 30.0,
             start_date: Date.today.iso8601, end_date: Date.today.iso8601 }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(400)
    end
  end

  describe "PUT /api/expenses/:id" do
    it "returns 401 without auth" do
      expense = create_expense(event: event, user: user)

      put "/api/expenses/#{expense[:id]}"

      expect(last_response.status).to eq(401)
    end

    it "returns 404 for non-existent expense" do
      put "/api/expenses/#{SecureRandom.uuid}",
          { description: "New" }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(404)
    end

    it "updates an expense when user is the creator" do
      expense = create_expense(event: event, user: user, description: "Old desc", amount: 50.0)

      put "/api/expenses/#{expense[:id]}",
          { description: "New desc", amount: 60.0,
            start_date: Date.today.iso8601, end_date: (Date.today + 3).iso8601 }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      updated = body["objects"].find { |o| o["objectType"] == "expense" }
      expect(updated["description"]).to eq("New desc")
      expect(updated["amount"]).to eq(60.0)
    end

    it "returns 403 when user is not the creator" do
      other_user = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: other_user)
      other_session = TestFactories.session(user: other_user)
      other_auth = { "HTTP_COOKIE" => "session_token=#{other_session[:token]}" }.merge(csrf_header)

      expense = create_expense(event: event, user: user, description: "Mine")

      put "/api/expenses/#{expense[:id]}",
          { description: "Stolen", amount: 100.0,
            start_date: Date.today.iso8601, end_date: Date.today.iso8601 }.to_json,
          other_auth.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end
  end

  describe "DELETE /api/expenses/:id" do
    it "returns 401 without auth" do
      expense = create_expense(event: event, user: user)

      delete "/api/expenses/#{expense[:id]}"

      expect(last_response.status).to eq(401)
    end

    it "returns 404 for non-existent expense" do
      delete "/api/expenses/#{SecureRandom.uuid}", {}, auth_headers

      expect(last_response.status).to eq(404)
    end

    it "deletes an expense when user is the creator" do
      expense = create_expense(event: event, user: user)

      delete "/api/expenses/#{expense[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:expenses].where(id: expense[:id]).count).to eq(0)
    end

    it "returns 403 when user is not the creator" do
      other_user = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: other_user)
      other_session = TestFactories.session(user: other_user)
      other_auth = { "HTTP_COOKIE" => "session_token=#{other_session[:token]}" }.merge(csrf_header)

      expense = create_expense(event: event, user: user)

      delete "/api/expenses/#{expense[:id]}", {}, other_auth

      expect(last_response.status).to eq(403)
    end
  end
end
