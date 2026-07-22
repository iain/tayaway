# frozen_string_literal: true

require "spec_helper"
require "webauthn/fake_client"

RSpec.describe "AdminApp" do
  def app
    AdminApp.freeze.app
  end

  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:json_headers) { csrf_header.merge("CONTENT_TYPE" => "application/json") }
  let(:fake_client) { WebAuthn::FakeClient.new("http://localhost:9393") }

  def admin_cookie(credential_id: nil)
    row = TestFactories.admin_session(credential_id: credential_id)
    { "HTTP_COOKIE" => "admin_session=#{row[:token]}" }
  end

  define_method(:enroll_via_routes) do |nickname: "MacBook", headers: json_headers|
    post "/enroll/begin", nil, headers
    begin_body = JSON.parse(last_response.body)
    credential = fake_client.create(challenge: begin_body["options"]["challenge"])

    post "/enroll/complete",
         { challengeToken: begin_body["challengeToken"], credential: credential, nickname: nickname }.to_json,
         headers
  end

  describe "GET /" do
    it "redirects to /enroll when no passkey is enrolled yet" do
      get "/"

      expect(last_response.status).to eq(302)
      expect(last_response.headers["Location"]).to end_with("/enroll")
    end

    it "redirects to /login without a session once enrolled" do
      TestFactories.admin_credential

      get "/"

      expect(last_response.status).to eq(302)
      expect(last_response.headers["Location"]).to end_with("/login")
    end

    it "redirects to /login with an expired session" do
      credential = TestFactories.admin_credential
      row = TestFactories.admin_session(credential_id: credential[:id], expires_at: Time.now - 60)

      get "/", {}, { "HTTP_COOKIE" => "admin_session=#{row[:token]}" }

      expect(last_response.status).to eq(302)
    end

    it "renders the dashboard, naming the signed-in device, with a valid session" do
      credential = TestFactories.admin_credential(nickname: "Operator MacBook")

      get "/", {}, admin_cookie(credential_id: credential[:id])

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Tayaway admin")
      expect(last_response.body).to include("Operator MacBook")
    end
  end

  describe "GET / panels" do
    it "renders the stat panels, leaving the detail listings to their own pages" do
      DB[:async_jobs].insert(
        job_class: "Dead::Job",
        args: Sequel.pg_jsonb({}),
        scheduled_at: Time.now,
        attempts: 5,
        dead_at: Time.now,
        last_error: "boom"
      )
      TestFactories.audit_log_entry(service: "Events::Update", outcome: "denied", error_code: "forbidden")

      get "/", {}, admin_cookie

      body = last_response.body
      expect(body).to include("Min supported")
      expect(body).to include("dead")
      expect(body).not_to include("Dead::Job")
      expect(body).not_to include("Events::Update")
    end
  end

  describe "static assets" do
    # The stylesheets have stable, undigested filenames. Without an explicit
    # revalidation header the browser caches them off Last-Modified alone, and
    # a restyle renders as the old CSS over the new markup.
    it "serves the stylesheet with a revalidation header" do
      get "/admin.css"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Cache-Control"]).to eq("no-cache")
    end
  end

  describe "GET /audit" do
    it "redirects to /login without a session" do
      get "/audit"

      expect(last_response.status).to eq(302)
    end

    it "lists entries and filters by outcome" do
      TestFactories.audit_log_entry(service: "Events::Create", outcome: "success")
      TestFactories.audit_log_entry(service: "Members::Remove", outcome: "denied")

      get "/audit", {}, admin_cookie
      expect(last_response.body).to include("Events::Create")
      expect(last_response.body).to include("Members::Remove")

      get "/audit", { "outcome" => "denied" }, admin_cookie
      expect(last_response.body).to include("Members::Remove")
      expect(last_response.body).not_to include("Events::Create")
    end
  end

  describe "GET /jobs" do
    def insert_job(job_class: "Some::Job", scheduled_at: Time.now - 60, attempts: 0, dead_at: nil, last_error: nil)
      DB[:async_jobs].returning(:id).insert(
        job_class: job_class,
        args: Sequel.pg_jsonb({ "email" => "a@b.c" }),
        scheduled_at: scheduled_at,
        attempts: attempts,
        dead_at: dead_at,
        last_error: last_error
      ).first[:id]
    end

    it "redirects to /login without a session" do
      get "/jobs"

      expect(last_response.status).to eq(302)
    end

    it "lists due jobs by default and filters by state" do
      insert_job(job_class: "Due::Job")
      insert_job(job_class: "Dead::Job", dead_at: Time.now, attempts: 5, last_error: "<script>alert(1)</script>")

      get "/jobs", {}, admin_cookie
      expect(last_response.body).to include("Due::Job")
      expect(last_response.body).not_to include("Dead::Job")

      get "/jobs", { "state" => "dead" }, admin_cookie
      expect(last_response.body).to include("Dead::Job")
      expect(last_response.body).not_to include("Due::Job")
      expect(last_response.body).not_to include("<script>alert(1)</script>")
    end

    it "falls back to due for an unknown state" do
      insert_job(job_class: "Due::Job")

      get "/jobs", { "state" => "bogus" }, admin_cookie

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Due::Job")
    end

    it "shows a job's details, escaping its error" do
      id = insert_job(job_class: "Detail::Job", attempts: 3, last_error: "<script>alert(1)</script>")

      get "/jobs/#{id}", {}, admin_cookie

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Detail::Job")
      expect(last_response.body).to include("a@b.c")
      expect(last_response.body).not_to include("<script>alert(1)</script>")
      expect(last_response.body).to include("&lt;script&gt;")
    end

    it "returns 404 for an unknown or malformed job id" do
      get "/jobs/#{SecureRandom.uuid}", {}, admin_cookie
      expect(last_response.status).to eq(404)

      get "/jobs/not-a-uuid", {}, admin_cookie
      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /enroll" do
    it "renders the enrollment page while the store is empty" do
      get "/enroll"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("passkey")
    end

    it "redirects to /login once enrolled and signed out" do
      TestFactories.admin_credential

      get "/enroll"

      expect(last_response.status).to eq(302)
      expect(last_response.headers["Location"]).to end_with("/login")
    end

    it "renders for a signed-in operator adding a device" do
      credential = TestFactories.admin_credential

      get "/enroll", {}, admin_cookie(credential_id: credential[:id])

      expect(last_response.status).to eq(200)
    end
  end

  describe "POST /enroll" do
    it "enrolls the first passkey and login works with it" do
      enroll_via_routes(nickname: "MacBook")

      expect(last_response.status).to eq(200)
      expect(Admin::State.db[:admin_credentials].first[:nickname]).to eq("MacBook")

      post "/login/begin", nil, json_headers
      begin_body = JSON.parse(last_response.body)
      assertion = fake_client.get(challenge: begin_body["options"]["challenge"])
      post "/login/complete",
           { challengeToken: begin_body["challengeToken"], credential: assertion }.to_json,
           json_headers

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Set-Cookie"]).to include("admin_session=")
    end

    it "returns 403 for unauthenticated enrollment once a credential exists" do
      TestFactories.admin_credential

      post "/enroll/begin", nil, json_headers

      expect(last_response.status).to eq(403)
    end

    it "allows a signed-in operator to enroll another device" do
      credential = TestFactories.admin_credential
      headers = json_headers.merge(admin_cookie(credential_id: credential[:id]))

      enroll_via_routes(nickname: "Phone", headers: headers)

      expect(last_response.status).to eq(200)
      expect(Admin::State.db[:admin_credentials].count).to eq(2)
    end
  end

  describe "POST /login/complete" do
    it "sets a strict admin session cookie" do
      enroll_via_routes

      post "/login/begin", nil, json_headers
      begin_body = JSON.parse(last_response.body)
      assertion = fake_client.get(challenge: begin_body["options"]["challenge"])
      post "/login/complete",
           { challengeToken: begin_body["challengeToken"], credential: assertion }.to_json,
           json_headers

      expect(last_response.status).to eq(200)
      cookie = last_response.headers["Set-Cookie"]
      expect(cookie).to include("admin_session=")
      expect(cookie.downcase).to include("httponly")
      expect(cookie.downcase).to include("samesite=strict")

      token = cookie[/admin_session=([^;]+)/, 1]
      get "/", {}, { "HTTP_COOKIE" => "admin_session=#{token}" }
      expect(last_response.status).to eq(200)
    end

    it "rejects a request without the CSRF header" do
      post "/login/begin", nil, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(403)
    end
  end

  describe "POST /logout" do
    it "deletes the session and clears the cookie" do
      cookie = admin_cookie

      post "/logout", nil, cookie.merge(csrf_header)

      expect(last_response.status).to eq(200)
      expect(Admin::State.db[:admin_sessions].count).to eq(0)
    end

    it "requires a session" do
      post "/logout", nil, csrf_header

      expect(last_response.status).to eq(401)
    end

    it "requires the CSRF header" do
      cookie = admin_cookie

      post "/logout", nil, cookie

      expect(last_response.status).to eq(403)
      expect(Admin::State.db[:admin_sessions].count).to eq(1)
    end
  end

  it "sets security headers on every response" do
    get "/login"

    expect(last_response.headers["Content-Security-Policy"]).to include("default-src 'none'")
    expect(last_response.headers["X-Frame-Options"]).to eq("DENY")
    expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end
end
