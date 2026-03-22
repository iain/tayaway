# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "User profile endpoint" do
  let(:user) { TestFactories.user(name: "Test User") }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:json_headers) { { "CONTENT_TYPE" => "application/json" }.merge(auth_cookie).merge(csrf_header) }
  let(:workspace) { TestFactories.workspace }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe "PUT /api/users/:id" do
    it "returns 401 without auth" do
      put "/api/users/#{user[:id]}", { name: "New Name" }.to_json,
          "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(401)
    end

    it "returns 403 when updating another user" do
      other_user = TestFactories.user

      put "/api/users/#{other_user[:id]}", { name: "Hacked" }.to_json, json_headers

      expect(last_response.status).to eq(403)
    end

    it "updates name" do
      put "/api/users/#{user[:id]}", { name: "New Name" }.to_json, json_headers

      expect(last_response.status).to eq(200)
      member = JSON.parse(last_response.body)["objects"].find { |o| o["objectType"] == "member" }
      expect(member["name"]).to eq("New Name")
    end

    it "treats empty latitude string as nil, not 0.0" do
      DB[:users].where(id: user[:id]).update(
        location_name: "Berlin",
        location_coordinates: Sequel.lit("point(13.405, 52.52)")
      )

      put "/api/users/#{user[:id]}", { name: "Test User", locationName: "", latitude: "", longitude: "" }.to_json,
          json_headers

      expect(last_response.status).to eq(200)
      member = JSON.parse(last_response.body)["objects"].find { |o| o["objectType"] == "member" }
      expect(member["latitude"]).to be_nil
      expect(member["longitude"]).to be_nil
    end

    it "does not set coordinates to 0.0 when empty strings are sent" do
      put "/api/users/#{user[:id]}", { name: "Test User", locationName: "London", latitude: "", longitude: "" }.to_json,
          json_headers

      expect(last_response.status).to eq(200)
      row = DB[:users].where(id: user[:id]).first
      # Empty lat/lng with a location name should not write a point(0,0) coordinate
      expect(row[:location_coordinates]).to be_nil
    end

    it "sets coordinates when valid lat/lng are provided" do
      put "/api/users/#{user[:id]}", {
        name: "Test User",
        locationName: "Berlin, Germany",
        latitude: "52.52",
        longitude: "13.405"
      }.to_json, json_headers

      expect(last_response.status).to eq(200)
      member = JSON.parse(last_response.body)["objects"].find { |o| o["objectType"] == "member" }
      expect(member["latitude"]).to be_within(0.001).of(52.52)
      expect(member["longitude"]).to be_within(0.001).of(13.405)
    end
  end
end
