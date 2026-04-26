# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auditable do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:membership) do
    row = TestFactories.workspace_membership(workspace: workspace, user: user)
    WorkspaceMembership.find(row[:id])
  end

  describe "via Events::Create (success path)" do
    it "records a single audit row with the actor, subject, and curated context" do
      result = Events::Create.call(
        workspace_id: workspace[:id], membership: membership, name: "Sprint Sync", description: "weekly"
      )
      expect(result.success?).to be true

      rows = DB[:audit_log_entries].where(service: "Events::Create").all
      expect(rows.size).to eq(1)

      row = rows.first
      expect(row[:outcome]).to eq("success")
      expect(row[:actor_kind]).to eq("user")
      expect(row[:actor_user_id]).to eq(user[:id])
      expect(row[:workspace_id]).to eq(workspace[:id])
      expect(row[:subject_type]).to eq("event")
      event_id = result.value![:objects].find { |o| o[:objectType] == "event" }[:id]
      expect(row[:subject_id]).to eq(event_id)
      expect(row[:action_params].to_h).to eq("name" => "Sprint Sync")
      expect(row[:error_code]).to be_nil
      expect(row[:error_message]).to be_nil
    end
  end

  describe "via Events::Update (denied path)" do
    it "records a denied row when the policy refuses the action" do
      stranger = TestFactories.user
      stranger_membership = WorkspaceMembership.find(
        TestFactories.workspace_membership(workspace: workspace, user: stranger)[:id]
      )
      event = TestFactories.event(workspace: workspace, user: user)

      result = Events::Update.call(
        event_id: event[:id], membership: stranger_membership, name: "Hijacked", description: nil
      )
      expect(result.failure?).to be true

      row = DB[:audit_log_entries].where(service: "Events::Update").first
      expect(row[:outcome]).to eq("denied")
      expect(row[:error_code]).to eq("forbidden")
      expect(row[:actor_user_id]).to eq(stranger[:id])
      expect(row[:subject_id]).to eq(event[:id])
    end
  end

  describe "via Events::Update (validation failure)" do
    it "records an error row with the validation message" do
      event = TestFactories.event(workspace: workspace, user: user)

      result = Events::Update.call(
        event_id: event[:id], membership: membership, name: "", description: nil
      )
      expect(result.failure?).to be true

      row = DB[:audit_log_entries].where(service: "Events::Update").first
      expect(row[:outcome]).to eq("error")
      expect(row[:error_code]).to eq("validation_error")
      expect(row[:error_message]).to eq("Name is required")
      expect(row[:subject_id]).to eq(event[:id])
    end
  end

  describe ".around" do
    it "suppresses cascaded inner calls so a service-of-services records one row at the outer frame" do
      outer_result = nil
      described_class.around(service: "Test::Outer", actor: membership, subject_type: "event") do
        outer_result = Events::Create.call(
          workspace_id: workspace[:id], membership: membership, name: "Inner", description: nil
        )
        outer_result
      end

      expect(outer_result.success?).to be true
      services = DB[:audit_log_entries].select_map(:service)
      expect(services).to eq(["Test::Outer"])
    end

    it "records actor_kind=system when no actor is given" do
      described_class.around(service: "Test::Cron", actor: nil) do
        Dry::Monads::Success({ objects: [] })
      end

      row = DB[:audit_log_entries].where(service: "Test::Cron").first
      expect(row[:actor_kind]).to eq("system")
      expect(row[:actor_user_id]).to be_nil
    end

    it "does not record a row when the block raises" do
      expect {
        described_class.around(service: "Test::Boom", actor: membership) do
          raise "kaboom"
        end
      }.to raise_error("kaboom")

      expect(DB[:audit_log_entries].where(service: "Test::Boom").count).to eq(0)

      # Cascade flag is left clean — a follow-up audited call still records.
      Events::Create.call(workspace_id: workspace[:id], membership: membership, name: "After", description: nil)
      expect(DB[:audit_log_entries].where(service: "Events::Create").count).to eq(1)
    end

    it "swallows audit insert failures without breaking the service result" do
      allow(AuditLogEntry).to receive(:create).and_raise("audit explosion")

      result = Events::Create.call(
        workspace_id: workspace[:id], membership: membership, name: "Resilient", description: nil
      )
      expect(result.success?).to be true
      expect(DB[:events].where(name: "Resilient").count).to eq(1)
    end

    it "extracts subject_id from a pool-shaped success when not given explicitly" do
      generated_id = SecureRandom.uuid
      described_class.around(service: "Test::Created", actor: membership, subject_type: "event") do
        Dry::Monads::Success({ objects: [{ id: generated_id, objectType: "event" }] })
      end

      row = DB[:audit_log_entries].where(service: "Test::Created").first
      expect(row[:subject_id]).to eq(generated_id)
    end
  end

  describe "RequestContext stamping" do
    after { RequestContext.reset! }

    it "stamps the audit row with the request_id and idempotency_key_hash from the surrounding context" do
      hash = Digest::SHA256.hexdigest("client-key")
      RequestContext.with(request_id: "req-123", idempotency_key_hash: hash) do
        Events::Create.call(
          workspace_id: workspace[:id], membership: membership, name: "Stamped", description: nil
        )
      end

      row = DB[:audit_log_entries].where(service: "Events::Create").first
      expect(row[:request_id]).to eq("req-123")
      expect(row[:idempotency_key_hash]).to eq(hash)
    end
  end

  describe "action_params truncation" do
    it "drops oversized payloads to a marker hash and still records the row" do
      huge = "x" * (AuditLogEntry::MAX_ACTION_PARAMS_BYTES + 1)
      AuditLogEntry.create(
        service: "Test::Bloat",
        outcome: "success",
        actor_kind: "system",
        action_params: { blob: huge }
      )

      row = DB[:audit_log_entries].where(service: "Test::Bloat").first
      payload = row[:action_params].to_h
      expect(payload).to include("_truncated" => true)
      expect(payload["_original_bytes"]).to be > AuditLogEntry::MAX_ACTION_PARAMS_BYTES
    end
  end
end
