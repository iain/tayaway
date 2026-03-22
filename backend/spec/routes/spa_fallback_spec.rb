# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SPA fallback" do
  before do
    FileUtils.mkdir_p(App::STATIC_DIR.to_s)
    File.write(App::STATIC_DIR.join("index.html"), "<html><body>App</body></html>")
  end

  after do
    FileUtils.rm_rf(App::STATIC_DIR.to_s)
  end

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
