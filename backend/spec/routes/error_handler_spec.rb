# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Global error handler" do
  it "returns a JSON error body with status 500 on unhandled exceptions" do
    allow(Session).to receive(:find_valid).and_raise(StandardError, "something went wrong")

    get "/api/auth/me", {}, { "HTTP_COOKIE" => "session_token=any-token" }

    expect(last_response.status).to eq(500)
    expect(JSON.parse(last_response.body)).to eq("error" => "Internal server error")
  end
end
