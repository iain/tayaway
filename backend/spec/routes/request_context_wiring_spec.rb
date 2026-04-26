# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Request context wiring" do
  describe ".resolve_request_id" do
    it "accepts a well-formed client-supplied X-Request-ID" do
      env = { "HTTP_X_REQUEST_ID" => "abc-123_DEF" }
      expect(App.resolve_request_id(env)).to eq("abc-123_DEF")
    end

    it "generates a UUID when no header is present" do
      expect(App.resolve_request_id({})).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "rejects a value with disallowed characters and falls back to a generated id" do
      env = { "HTTP_X_REQUEST_ID" => "abc<script>" }
      expect(App.resolve_request_id(env)).not_to eq("abc<script>")
      expect(App.resolve_request_id(env)).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "rejects an over-long value" do
      env = { "HTTP_X_REQUEST_ID" => "a" * 129 }
      expect(App.resolve_request_id(env)).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "rejects an empty string" do
      env = { "HTTP_X_REQUEST_ID" => "" }
      expect(App.resolve_request_id(env)).to match(/\A[0-9a-f-]{36}\z/)
    end
  end

  describe "end-to-end stamping through a real request" do
    let(:user) { TestFactories.user }
    let(:session) { TestFactories.session(user: user) }
    let(:workspace) { TestFactories.workspace }

    before { TestFactories.workspace_membership(workspace: workspace, user: user, role: "owner") }

    def auth_env(extra = {})
      {
        "HTTP_COOKIE" => "session_token=#{session[:token]}",
        "HTTP_X_CSRF_PROTECTION" => "1",
        "CONTENT_TYPE" => "application/json"
      }.merge(extra)
    end

    it "stamps the audit row with the request_id from X-Request-ID and the idempotency_key_hash from Idempotency-Key" do
      post "/api/events",
           { workspace_id: workspace[:id], name: "Stamped" }.to_json,
           auth_env("HTTP_X_REQUEST_ID" => "trace-abcdef", "HTTP_IDEMPOTENCY_KEY" => "client-key-123")

      expect(last_response.status).to be_between(200, 299)

      row = DB[:audit_log_entries].where(service: "Events::Create").first
      expect(row).not_to be_nil
      expect(row[:request_id]).to eq("trace-abcdef")
      expect(row[:idempotency_key_hash]).to eq(Digest::SHA256.hexdigest("client-key-123"))
    end

    it "generates a request_id when no X-Request-ID header is sent" do
      post "/api/events",
           { workspace_id: workspace[:id], name: "Generated" }.to_json,
           auth_env

      row = DB[:audit_log_entries].where(service: "Events::Create").first
      expect(row).not_to be_nil
      expect(row[:request_id]).to match(/\A[0-9a-f-]{36}\z/)
      expect(row[:idempotency_key_hash]).to be_nil
    end
  end
end
