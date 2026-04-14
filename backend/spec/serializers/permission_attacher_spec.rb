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

    it "swallows policy errors and logs them, returning the hash without permissions" do
      allow(APP_LOGGER).to receive(:error)
      allow(EventPolicy).to receive(:new).and_raise(StandardError, "boom")

      result = described_class.call(event_hash, raw_object: event, membership: owner_membership)

      expect(result).not_to have_key(:permissions)
      expect(APP_LOGGER).to have_received(:error)
    end
  end

  describe ".attach_to_message" do
    # Referencing ConnectionManager triggers Zeitwerk to load connection_manager.rb,
    # which defines the Websocket::PolicyContext struct as a side effect.
    before { Websocket::ConnectionManager }

    let(:policy_context) do
      Websocket::PolicyContext.new(
        raw_objects: { "event" => event },
        kwargs: { has_expenses: false }
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

    it "skips objects whose type is not in the registry" do
      unknown_msg = message.merge(
        data: { objects: [{ id: "1", objectType: "notAType" }] }
      )
      result = described_class.attach_to_message(unknown_msg, owner_membership, policy_context)

      expect(result[:data][:objects].first).not_to have_key(:permissions)
    end
  end
end
