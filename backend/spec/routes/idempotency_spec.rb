# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Idempotency-Key handling" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:json_header) { { "CONTENT_TYPE" => "application/json" } }
  let(:headers) { auth_cookie.merge(csrf_header).merge(json_header) }

  let(:workspace) { TestFactories.workspace }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }
  let(:idempotency_key) { SecureRandom.uuid }

  before do
    TestFactories.workspace_membership(workspace: workspace, user: user)
    now = Time.now
    DB[:rsvps].insert(
      id: SecureRandom.uuid, event_id: event[:id], user_id: user[:id],
      attending: true, created_at: now, updated_at: now
    )
  end

  def post_expense(key:, description: "Groceries", amount: 75.50, user_headers: headers)
    post "/api/expenses",
         { event_id: event[:id], description: description, amount: amount,
           start_date: Date.today.iso8601, end_date: (Date.today + 2).iso8601 }.to_json,
         user_headers.merge("HTTP_IDEMPOTENCY_KEY" => key)
  end

  it "runs the service on the first request and caches the response" do
    expect { post_expense(key: idempotency_key) }
      .to change { DB[:expenses].count }.by(1)
      .and change { DB[:idempotency_keys].count }.by(1)

    expect(last_response.status).to eq(201)
  end

  it "replays the cached response on a duplicate request without re-running the service" do
    allow(Expenses::Create).to receive(:call).and_call_original

    post_expense(key: idempotency_key)
    first_status = last_response.status
    first_body = last_response.body

    expect { post_expense(key: idempotency_key) }
      .not_to(change { DB[:expenses].count })

    # The whole point of replay: the service must run exactly once even
    # though the client made the same call twice. Counting `expenses` rows
    # alone would miss any service-level side effect (broadcast, mailer,
    # third-party call) that doesn't happen to write to that table.
    expect(Expenses::Create).to have_received(:call).once

    expect(last_response.status).to eq(first_status)
    expect(last_response.body).to eq(first_body)
  end

  it "rejects a duplicate key when the request body differs" do
    post_expense(key: idempotency_key, description: "Groceries")

    post_expense(key: idempotency_key, description: "Something else")

    expect(last_response.status).to eq(422)
    body = JSON.parse(last_response.body)
    expect(body["error"]).to match(/idempotency key/i)
  end

  it "treats the same key from a different user as a fresh request" do
    post_expense(key: idempotency_key)
    expect(last_response.status).to eq(201)

    other_user = TestFactories.user
    TestFactories.workspace_membership(workspace: workspace, user: other_user)
    now = Time.now
    DB[:rsvps].insert(
      id: SecureRandom.uuid, event_id: event[:id], user_id: other_user[:id],
      attending: true, created_at: now, updated_at: now
    )
    other_session = TestFactories.session(user: other_user)
    other_headers = {
      "HTTP_COOKIE" => "session_token=#{other_session[:token]}",
    }.merge(csrf_header).merge(json_header)

    expect { post_expense(key: idempotency_key, user_headers: other_headers) }
      .to change { DB[:expenses].count }.by(1)
      .and change { DB[:idempotency_keys].count }.by(1)

    expect(last_response.status).to eq(201)
  end

  it "treats an expired key as a fresh request" do
    post_expense(key: idempotency_key)
    expect(DB[:expenses].count).to eq(1)

    DB[:idempotency_keys]
      .where(user_id: user[:id], idempotency_key_hash: Idempotency.digest(idempotency_key))
      .delete

    expect { post_expense(key: idempotency_key) }
      .to change { DB[:expenses].count }.by(1)

    expect(last_response.status).to eq(201)
  end

  it "returns 409 with a JSON error when the wrapper signals an in-flight conflict" do
    allow(Idempotency).to receive(:wrap).and_raise(Idempotency::ConflictError, "in flight")

    post_expense(key: idempotency_key)

    expect(last_response.status).to eq(409)
    body = JSON.parse(last_response.body)
    expect(body["error"]).to match(/in flight/i)
  end

  it "skips idempotency handling when no header is sent" do
    post "/api/expenses",
         { event_id: event[:id], description: "Groceries", amount: 75.50,
           start_date: Date.today.iso8601, end_date: (Date.today + 2).iso8601 }.to_json,
         headers

    expect(last_response.status).to eq(201)
    expect(DB[:idempotency_keys].count).to eq(0)
  end
end
