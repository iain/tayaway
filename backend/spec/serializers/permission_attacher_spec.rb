# frozen_string_literal: true

require "spec_helper"

RSpec.describe PermissionAttacher do
  let(:workspace) { TestFactories.workspace }
  let(:owner) { TestFactories.user }
  let(:owner_membership) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: owner)[:id]) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: owner) }
  let(:event) { Event.find(event_row[:id]) }
  let(:event_hash) { { id: event.id.to_s, objectType: "event", name: event.name } }

  describe ".call" do
    it "merges permissions from the policy for the given membership" do
      result = described_class.call(event_hash, raw_object: event, membership: owner_membership)

      expect(result[:permissions][:edit]).to eq({ allowed: true })
      expect(result[:permissions][:delete]).to eq({ allowed: true })
    end

    it "uses policy_context kwargs to influence permissions" do
      result = described_class.call(
        event_hash, raw_object: event, membership: owner_membership,
        policy_context: { has_expenses: true }
      )

      expect(result[:permissions][:delete]).to eq({ allowed: false, reason: "has_expenses" })
    end

    it "returns the original hash unchanged when membership is nil" do
      result = described_class.call(event_hash, raw_object: event, membership: nil)

      expect(result).not_to have_key(:permissions)
    end

    it "returns the original hash unchanged when objectType is not in the registry" do
      unknown_hash = { id: "1", objectType: "notAType" }
      result = described_class.call(unknown_hash, raw_object: nil, membership: owner_membership)

      expect(result).to eq(unknown_hash)
    end

    it "propagates unexpected policy errors so sync requests fail loudly" do
      allow(EventPolicy).to receive(:new).and_raise(NoMethodError, "boom")

      expect {
        described_class.call(event_hash, raw_object: event, membership: owner_membership)
      }.to raise_error(NoMethodError, "boom")
    end

    it "rescues NameError from an unloaded policy class, logs, and returns the hash unchanged" do
      allow(APP_LOGGER).to receive(:error)
      entry = ObjectRegistry::BY_CLIENT_TYPE["event"]
      allow(entry).to receive(:policy).and_return("NotARealPolicy")

      result = described_class.call(event_hash, raw_object: event, membership: owner_membership)

      expect(result).not_to have_key(:permissions)
      expect(APP_LOGGER).to have_received(:error)
    end
  end

  describe ".attach_to_message" do
    let(:policy_context) do
      Websocket::PolicyContext.new(
        raw_objects: { "event:#{event.id}" => event },
        policy_contexts: { "event:#{event.id}" => { has_expenses: false } }
      )
    end

    let(:message) do
      {
        type: "broadcast",
        workspaceId: workspace[:id].to_s,
        action: "update",
        data: { objects: [event_hash] }
      }
    end

    it "attaches permissions to every object in the message data" do
      result = described_class.attach_to_message(message, owner_membership, policy_context)

      obj = result[:data][:objects].first
      expect(obj[:permissions][:edit]).to eq({ allowed: true })
    end

    it "returns the message unchanged when membership is nil" do
      result = described_class.attach_to_message(message, nil, policy_context)

      expect(result).to eq(message)
    end

    it "does not mutate the original message" do
      original_snapshot = Marshal.dump(message)
      described_class.attach_to_message(message, owner_membership, policy_context)

      expect(Marshal.dump(message)).to eq(original_snapshot)
    end

    it "logs and ships the object unchanged when its type is not in the registry" do
      allow(APP_LOGGER).to receive(:error)
      unknown_msg = message.merge(
        data: { objects: [{ id: "1", objectType: "notAType" }] }
      )
      result = described_class.attach_to_message(unknown_msg, owner_membership, policy_context)

      expect(result[:data][:objects].first).not_to have_key(:permissions)
      expect(APP_LOGGER).to have_received(:error)
    end

    it "logs and ships the object unchanged when the PolicyContext is missing its raw_object" do
      # Exercises the old fan-out-drift bug: a payload object whose raw_object
      # wasn't carried into the PolicyContext used to silently ship without
      # permissions. Now it raises internally, the per-object rescue catches
      # the failure, logs it with enough context to diagnose, and the object
      # ships unpermissioned on that single recipient — the rest of the
      # broadcast still goes out cleanly.
      allow(APP_LOGGER).to receive(:error)
      bare_context = Websocket::PolicyContext.new(raw_objects: {}, policy_contexts: {})

      result = described_class.attach_to_message(message, owner_membership, bare_context)

      expect(result[:data][:objects].first).not_to have_key(:permissions)
      expect(APP_LOGGER).to have_received(:error).with(any_args)
    end

    it "isolates per-object policy failures so one bad object does not break the whole broadcast" do
      # Two failing objects: the event whose EventPolicy.new raises, and an
      # unknown-type object that fails entry lookup. Both paths must be
      # logged + isolated so neither pollutes the other recipient's payload.
      allow(APP_LOGGER).to receive(:error)
      allow(EventPolicy).to receive(:new).and_raise(NoMethodError, "boom")
      other_hash = { id: SecureRandom.uuid, objectType: "unknown" }
      msg = message.merge(data: { objects: [event_hash, other_hash] })

      result = described_class.attach_to_message(msg, owner_membership, policy_context)

      expect(result[:data][:objects].length).to eq(2)
      expect(result[:data][:objects][0]).not_to have_key(:permissions)
      expect(result[:data][:objects][1]).to eq(other_hash)
      expect(APP_LOGGER).to have_received(:error).at_least(:once)
    end

    it "attaches permissions for fan-out children using their own raw_objects" do
      # Regression guard for the fan-out-drift bug. When a parent serializer
      # pushes children into the pool (chore_roster → chores), the broadcast
      # payload must ship with permissions computed for each child as well
      # as the parent — not just the notify target.
      roster = TestFactories.chore_roster(event: event_row, user: owner)
      chore_row = TestFactories.chore(chore_roster: roster)
      roster_model = ChoreRoster.find(roster[:id])
      chore_model = Chore.find(chore_row[:id])

      parent_hash = { id: roster_model.id.to_s, objectType: "choreRoster", name: "R" }
      child_hash = { id: chore_model.id.to_s, objectType: "chore", name: chore_model.name }
      multi_msg = {
        type: "broadcast",
        workspaceId: workspace[:id].to_s,
        action: "update",
        data: { objects: [parent_hash, child_hash] }
      }

      ctx = Websocket::PolicyContext.new(
        raw_objects: {
          "chore_roster:#{roster_model.id}" => roster_model,
          "chore:#{chore_model.id}" => chore_model
        },
        policy_contexts: {}
      )

      result = described_class.attach_to_message(multi_msg, owner_membership, ctx)

      expect(result[:data][:objects].first[:permissions]).to be_a(Hash)
      expect(result[:data][:objects].last[:permissions]).to be_a(Hash)
    end
  end
end
