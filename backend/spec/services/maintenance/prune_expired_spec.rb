# frozen_string_literal: true

require "spec_helper"

RSpec.describe Maintenance::PruneExpired do
  describe ".call" do
    it "deletes expired sessions and keeps live ones" do
      live = TestFactories.session(expires_at: Time.now + 3600)
      dead = TestFactories.session(expires_at: Time.now - 1)

      described_class.call

      expect(DB[:sessions].select_map(:id)).to eq([live[:id]])
      expect(DB[:sessions].where(id: dead[:id]).count).to eq(0)
    end

    it "deletes expired admin_sessions and keeps live ones" do
      live = TestFactories.admin_session(expires_at: Time.now + 3600)
      TestFactories.admin_session(expires_at: Time.now - 1)

      described_class.call

      expect(DB[:admin_sessions].select_map(:id)).to eq([live[:id]])
    end

    it "deletes ws_tickets that are expired or already used, keeping live unused ones" do
      TestFactories.ws_ticket(expires_at: Time.now + 60, used_at: nil, id: "11111111-1111-1111-1111-111111111111")
      TestFactories.ws_ticket(expires_at: Time.now - 1,  used_at: nil, id: "22222222-2222-2222-2222-222222222222")
      TestFactories.ws_ticket(expires_at: Time.now + 60, used_at: Time.now, id: "33333333-3333-3333-3333-333333333333")

      described_class.call

      expect(DB[:ws_tickets].select_map(:id)).to eq(["11111111-1111-1111-1111-111111111111"])
    end

    it "deletes login_link_tokens that are expired or already used, keeping live unused ones" do
      live = TestFactories.login_link_token(expires_at: Time.now + 60, used_at: nil).record
      TestFactories.login_link_token(expires_at: Time.now - 1, used_at: nil)
      TestFactories.login_link_token(expires_at: Time.now + 60, used_at: Time.now)

      described_class.call

      expect(DB[:login_link_tokens].select_map(:id)).to eq([live.id.to_s])
    end

    it "deletes email_change_tokens that are expired or already used, keeping live unused ones" do
      live = TestFactories.email_change_token(expires_at: Time.now + 60, used_at: nil).record
      TestFactories.email_change_token(expires_at: Time.now - 1, used_at: nil)
      TestFactories.email_change_token(expires_at: Time.now + 60, used_at: Time.now)

      described_class.call

      expect(DB[:email_change_tokens].select_map(:id)).to eq([live.id.to_s])
    end

    it "deletes workspace_invites that are expired or accepted, keeping live pending ones" do
      pending = TestFactories.workspace_invite(expires_at: Time.now + 3600, accepted_at: nil)
      TestFactories.workspace_invite(expires_at: Time.now - 1, accepted_at: nil)
      TestFactories.workspace_invite(expires_at: Time.now + 3600, accepted_at: Time.now)

      described_class.call

      expect(DB[:workspace_invites].select_map(:id)).to eq([pending[:id]])
    end

    it "deletes idempotency_keys older than the 24h retention window" do
      user = TestFactories.user
      insert_idempotency_key(user, "fresh", created_at: Time.now - 3600)
      insert_idempotency_key(user, "stale", created_at: Time.now - (25 * 3600))

      described_class.call

      expect(DB[:idempotency_keys].select_map(:request_fingerprint)).to eq(["fresh"])
    end

    it "deletes deleted_items tombstones older than the partial-sync retention window" do
      recent = insert_deleted_item(deleted_at: Time.now - 3600)
      old = insert_deleted_item(deleted_at: Time.now - Sync::WorkspaceSync::RETENTION_PERIOD - 3600)

      described_class.call

      expect(DB[:deleted_items].select_map(:id)).to eq([recent])
      expect(DB[:deleted_items].where(id: old).count).to eq(0)
    end

    it "returns the number of rows deleted per table" do
      TestFactories.session(expires_at: Time.now - 1)
      TestFactories.session(expires_at: Time.now - 1)

      result = described_class.call

      expect(result[:sessions]).to eq(2)
      expect(result[:ws_tickets]).to eq(0)
    end
  end

  describe ".ensure_scheduled" do
    before { DB[Jobs::Queue::TABLE].delete }

    it "schedules a prune job when none is pending" do
      expect { described_class.ensure_scheduled }
        .to change(pending_jobs, :count).from(0).to(1)
    end

    it "preserves the existing schedule rather than resetting the timer" do
      described_class.ensure_scheduled
      first = pending_jobs.get(:scheduled_at)

      described_class.ensure_scheduled

      expect(pending_jobs.count).to eq(1)
      expect(pending_jobs.get(:scheduled_at)).to eq(first)
    end

    it "re-seeds past a dead job, self-healing a broken chain" do
      DB[Jobs::Queue::TABLE].insert(
        job_class: described_class::JOB_CLASS,
        args: Sequel.pg_jsonb({}),
        scheduled_at: Time.now,
        dead_at: Time.now
      )

      expect { described_class.ensure_scheduled }.to change(pending_jobs, :count).from(0).to(1)
    end
  end

  describe described_class::Job do
    before { DB[Jobs::Queue::TABLE].delete }

    it "prunes and reschedules a day out when the worker runs a due job" do
      dead = TestFactories.session(expires_at: Time.now - 1)
      DB[Jobs::Queue::TABLE].insert(
        job_class: Maintenance::PruneExpired::JOB_CLASS,
        args: Sequel.pg_jsonb({}),
        scheduled_at: Time.now - 1
      )

      Jobs::Worker.drain

      expect(DB[:sessions].where(id: dead[:id]).count).to eq(0)
      # The completed run is deleted; only the freshly-queued next run remains.
      rows = DB[Jobs::Queue::TABLE].where(job_class: Maintenance::PruneExpired::JOB_CLASS).all
      expect(rows.size).to eq(1)
      expect(rows.first[:scheduled_at]).to be_within(3600).of(Time.now + Maintenance::PruneExpired::INTERVAL)
    end

    it "leaves a single pending job even if strays were queued" do
      2.times do
        DB[Jobs::Queue::TABLE].insert(
          job_class: Maintenance::PruneExpired::JOB_CLASS,
          args: Sequel.pg_jsonb({}),
          scheduled_at: Time.now
        )
      end

      described_class.new.call

      expect(DB[Jobs::Queue::TABLE].where(job_class: Maintenance::PruneExpired::JOB_CLASS, locked_at: nil).count).to eq(1)
    end
  end

  def pending_jobs
    DB[Jobs::Queue::TABLE].where(job_class: described_class::JOB_CLASS, dead_at: nil)
  end

  def insert_idempotency_key(user, fingerprint, created_at:)
    DB[:idempotency_keys].insert(
      user_id: user[:id],
      idempotency_key_hash: Digest::SHA256.hexdigest(fingerprint),
      request_fingerprint: fingerprint,
      response_status: 200,
      response_body: "{}",
      created_at: created_at
    )
  end

  def insert_deleted_item(deleted_at:)
    id = SecureRandom.uuid
    DB[:deleted_items].insert(
      id: id,
      workspace_id: SecureRandom.uuid,
      object_type: "event",
      object_id: SecureRandom.uuid,
      deleted_at: deleted_at
    )
    id
  end
end
