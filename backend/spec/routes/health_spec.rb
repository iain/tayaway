# typed: true
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Health endpoint" do
  describe "GET /health" do
    it "returns healthy status" do
      get "/health"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq("status" => "healthy")
    end
  end

  describe "GET /api/health" do
    it "returns healthy status" do
      get "/api/health"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq("status" => "healthy")
    end
  end
end
