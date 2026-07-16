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

    it "lists dead jobs newest first" do
      insert_job(dead_at: Time.now - 3600, job_class: "Old::Job")
      insert_job(dead_at: Time.now, job_class: "New::Job")

      dead = described_class.jobs[:dead_jobs]

      expect(dead.map { |j| j[:job_class] }).to eq(["New::Job", "Old::Job"])
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
