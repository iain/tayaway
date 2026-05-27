# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Health endpoint" do
  describe "GET /health" do
    it "returns healthy status when database is reachable" do
      get "/health"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to include("status" => "healthy")
    end

    it "reports the deployed build version" do
      get "/health"

      expect(JSON.parse(last_response.body)["version"]).to eq(APP_CONFIG.git_sha)
    end

    it "returns 503 when database is unreachable" do
      allow(DB).to receive(:test_connection).and_raise(Sequel::Error.new("connection refused"))

      get "/health"

      expect(last_response.status).to eq(503)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("unhealthy")
      expect(body["reason"]).to eq("database")
    end
  end

  describe "GET /api/health" do
    it "returns healthy status" do
      get "/api/health"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to include("status" => "healthy")
    end

    it "reports the deployed build version" do
      get "/api/health"

      expect(JSON.parse(last_response.body)["version"]).to eq(APP_CONFIG.git_sha)
    end
  end
end
