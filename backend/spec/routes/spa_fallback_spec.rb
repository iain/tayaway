# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SPA fallback" do
  describe "GET /" do
    it "returns Cache-Control: no-cache to prevent stale index.html after deploy" do
      get "/"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Cache-Control"]).to eq("no-cache, no-store, must-revalidate")
    end
  end

  describe "GET /events/:id" do
    it "returns Cache-Control: no-cache for deep SPA routes" do
      get "/events/some-event-id"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Cache-Control"]).to eq("no-cache, no-store, must-revalidate")
    end
  end
end
