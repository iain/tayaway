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

  describe "cascade suppression" do
    it "does not record a second row when an audited service is invoked from inside another audited service" do
      cascading_service = Module.new do
        extend Auditable

        audit subject_type: "event"

        class << self
          include Dry::Monads[:result]

          def name = "TestCascade::Outer"

          def call(workspace_id:, membership:, name:, description:)
            Events::Create.call(workspace_id: workspace_id, membership: membership, name: name, description: description)
          end
        end
      end
      stub_const("TestCascade", Module.new)
      stub_const("TestCascade::Outer", cascading_service)

      result = cascading_service.call(
        workspace_id: workspace[:id], membership: membership, name: "Once", description: nil
      )
      expect(result.success?).to be true

      services = DB[:audit_log_entries].select_map(:service)
      expect(services).to eq(["TestCascade::Outer"])
    end
  end

  describe "system actor" do
    it "records actor_kind=system when no membership is passed" do
      headless_service = Module.new do
        extend Auditable

        audit subject_type: "event"

        class << self
          include Dry::Monads[:result]

          def name = "TestSystem::Tick"

          def call(**)
            Success({ objects: [] })
          end
        end
      end
      stub_const("TestSystem", Module.new)
      stub_const("TestSystem::Tick", headless_service)

      headless_service.call

      row = DB[:audit_log_entries].where(service: "TestSystem::Tick").first
      expect(row[:actor_kind]).to eq("system")
      expect(row[:actor_user_id]).to be_nil
    end
  end

  describe "rescue behaviour" do
    it "swallows audit insert failures without breaking the service result" do
      allow(AuditLogEntry).to receive(:create).and_raise("audit explosion")

      result = Events::Create.call(
        workspace_id: workspace[:id], membership: membership, name: "Resilient", description: nil
      )
      expect(result.success?).to be true
      expect(DB[:events].where(name: "Resilient").count).to eq(1)
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
