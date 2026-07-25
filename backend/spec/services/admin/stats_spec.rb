# frozen_string_literal: true

require "spec_helper"

RSpec.describe Admin::Stats do
  def insert_job(scheduled_at: Time.now - 60, attempts: 0, dead_at: nil, last_error: nil, job_class: "Test::Job")
    DB[:async_jobs].insert(
      job_class: job_class,
      args: Sequel.pg_jsonb({}),
      scheduled_at: scheduled_at,
      attempts: attempts,
      dead_at: dead_at,
      last_error: last_error
    )
  end

  describe ".jobs" do
    it "counts due, scheduled, retrying, and dead jobs" do
      insert_job(scheduled_at: Time.now - 60)
      insert_job(scheduled_at: Time.now + 3600)
      insert_job(scheduled_at: Time.now + 60, attempts: 2, last_error: "boom")
      insert_job(dead_at: Time.now, attempts: 5, last_error: "dead boom")

      stats = described_class.jobs

      expect(stats[:due]).to eq(1)
      expect(stats[:scheduled]).to eq(2)
      expect(stats[:retrying]).to eq(1)
      expect(stats[:dead]).to eq(1)
    end
  end

  describe ".job_list" do
    it "selects the rows behind each dashboard counter" do
      insert_job(scheduled_at: Time.now - 60, job_class: "Due::Job")
      insert_job(scheduled_at: Time.now + 3600, job_class: "Scheduled::Job")
      insert_job(scheduled_at: Time.now + 60, attempts: 2, last_error: "boom", job_class: "Retrying::Job")
      insert_job(dead_at: Time.now, attempts: 5, last_error: "dead boom", job_class: "Dead::Job")

      by_state = Admin::Stats::JOB_STATES.to_h { |state| [state, described_class.job_list(state: state)] }

      expect(by_state["due"].map { |j| j[:job_class] }).to eq(["Due::Job"])
      expect(by_state["scheduled"].map { |j| j[:job_class] }).to contain_exactly("Scheduled::Job", "Retrying::Job")
      expect(by_state["retrying"].map { |j| j[:job_class] }).to eq(["Retrying::Job"])
      expect(by_state["dead"].map { |j| j[:job_class] }).to eq(["Dead::Job"])
    end

    it "orders due jobs oldest first and dead jobs newest first" do
      insert_job(scheduled_at: Time.now - 60, job_class: "Newer::Job")
      insert_job(scheduled_at: Time.now - 3600, job_class: "Older::Job")
      insert_job(dead_at: Time.now - 3600, job_class: "OldDead::Job")
      insert_job(dead_at: Time.now, job_class: "NewDead::Job")

      expect(described_class.job_list(state: "due").map { |j| j[:job_class] })
        .to eq(["Older::Job", "Newer::Job"])
      expect(described_class.job_list(state: "dead").map { |j| j[:job_class] })
        .to eq(["NewDead::Job", "OldDead::Job"])
    end
  end

  describe ".job" do
    it "returns the full row for a single job" do
      id = DB[:async_jobs].returning(:id).insert(
        job_class: "Detail::Job",
        args: Sequel.pg_jsonb({ "email" => "a@b.c" }),
        scheduled_at: Time.now,
        attempts: 1,
        last_error: "boom"
      ).first[:id]

      job = described_class.job(id)

      expect(job[:job_class]).to eq("Detail::Job")
      expect(job[:args]).to eq({ "email" => "a@b.c" })
      expect(job[:last_error]).to eq("boom")
    end

    it "returns nil for an unknown or malformed id" do
      expect(described_class.job(SecureRandom.uuid)).to be_nil
      expect(described_class.job("not-a-uuid")).to be_nil
    end
  end

  describe ".users" do
    it "counts users, signups, and active sessions" do
      old_user = TestFactories.user
      DB[:users].where(id: old_user[:id]).update(created_at: Time.now - (60 * 86_400))
      recent_user = TestFactories.user

      session = TestFactories.session(user: recent_user)
      DB[:sessions].where(id: session[:id]).update(last_active_at: Time.now - 3600)
      TestFactories.session(user: old_user, expires_at: Time.now - 60)

      stats = described_class.users

      expect(stats[:total]).to eq(2)
      expect(stats[:new_last_30d]).to eq(1)
      expect(stats[:active_sessions]).to eq(1)
      expect(stats[:active_users_7d]).to eq(1)
    end
  end

  describe ".client_versions" do
    it "buckets active sessions by last seen client version" do
      user = TestFactories.user
      v2_a = TestFactories.session(user: user)
      v2_b = TestFactories.session(user: TestFactories.user)
      unknown = TestFactories.session(user: TestFactories.user)
      expired = TestFactories.session(user: user, expires_at: Time.now - 60)
      DB[:sessions].where(id: [v2_a[:id], v2_b[:id]]).update(last_seen_client_version: 2)
      DB[:sessions].where(id: expired[:id]).update(last_seen_client_version: 1)
      DB[:sessions].where(id: unknown[:id]).update(last_seen_client_version: nil)

      stats = described_class.client_versions

      expect(stats[:min_supported]).to eq(ClientProtocol::MIN_SUPPORTED_VERSION)
      v2 = stats[:buckets].find { |b| b[:version] == 2 }
      expect(v2[:sessions]).to eq(2)
      expect(v2[:users]).to eq(2)
      expect(stats[:buckets].find { |b| b[:version].nil? }[:sessions]).to eq(1)
      expect(stats[:buckets].sum { |b| b[:sessions] }).to eq(3)
    end
  end

  describe ".csp_reports" do
    def insert_csp_report(blocked_uri:, directive: "script-src", disposition: "enforce", count: 1, last_seen_at: Time.now)
      DB[:csp_reports].insert(
        disposition: disposition,
        directive: directive,
        blocked_uri: blocked_uri,
        document_uri: "/",
        count: count,
        first_seen_at: last_seen_at,
        last_seen_at: last_seen_at,
        sample: Sequel.pg_jsonb({ "sourceFile" => "/assets/index.js" })
      )
    end

    it "returns violations most recently seen first" do
      insert_csp_report(blocked_uri: "https://old.example", last_seen_at: Time.now - 3600)
      insert_csp_report(blocked_uri: "https://new.example")

      rows = described_class.csp_reports

      expect(rows.map { |r| r[:blocked_uri] }).to eq(["https://new.example", "https://old.example"])
    end

    it "filters by disposition" do
      insert_csp_report(blocked_uri: "https://blocked.example", disposition: "enforce")
      insert_csp_report(blocked_uri: "https://would-block.example", disposition: "report")

      rows = described_class.csp_reports(disposition: "report")

      expect(rows.map { |r| r[:blocked_uri] }).to eq(["https://would-block.example"])
    end

    it "summarises distinct violations and total hits" do
      insert_csp_report(blocked_uri: "https://a.example", count: 3)
      insert_csp_report(blocked_uri: "https://b.example", count: 4, last_seen_at: Time.now - (10 * 86_400))

      expect(described_class.csp_summary).to include(violations: 2, hits: 7, hits_last_7d: 3)
    end
  end

  describe ".audit" do
    it "returns recent entries newest first with actor emails" do
      actor = TestFactories.user(email: "actor@example.com")
      TestFactories.audit_log_entry(service: "Events::Create", created_at: Time.now - 60)
      TestFactories.audit_log_entry(service: "Events::Update", actor_user: actor)

      entries = described_class.audit

      expect(entries.map { |e| e[:service] }).to eq(["Events::Update", "Events::Create"])
      expect(entries.first[:actor_email]).to eq("actor@example.com")
      expect(entries.last[:actor_email]).to be_nil
    end

    it "filters by outcome" do
      TestFactories.audit_log_entry(outcome: "success")
      TestFactories.audit_log_entry(outcome: "denied", error_code: "forbidden")

      entries = described_class.audit(outcome: "denied")

      expect(entries.length).to eq(1)
      expect(entries.first[:outcome]).to eq("denied")
    end
  end
end
