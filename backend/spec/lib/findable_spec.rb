# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Findable do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  # Use Event as a representative model that includes Findable.
  describe "Event.find_result" do
    let(:event_row) { TestFactories.event(workspace: workspace, user: user) }

    it "returns Success when the record exists" do
      event_row # create the record
      result = Event.find_result(event_row[:id])

      expect(result.success?).to be true
      expect(result.value!).to be_a(Event)
      expect(result.value!.id.to_s).to eq(event_row[:id])
    end

    it "returns Failure with not_found status when the record does not exist" do
      id = SecureRandom.uuid
      result = Event.find_result(id)

      expect(result.failure?).to be true
      expect(result.failure.http_status).to eq(404)
      expect(result.failure.message).to eq("Event not found")
    end

    it "returns Failure with gone status when the record is in deleted_items" do
      id = SecureRandom.uuid
      DB[:deleted_items].insert(
        workspace_id: workspace[:id],
        object_type: "event",
        object_id: id,
        deleted_at: Time.now
      )

      result = Event.find_result(id)

      expect(result.failure?).to be true
      expect(result.failure.http_status).to eq(410)
      expect(result.failure.message).to eq("Event not found")
    end
  end

  # Test multi-word class names to verify correct object_type and label derivation.
  describe "SettlementTransfer.find_result" do
    # SettlementTransfer → object_type "settlement_transfer", label "Settlement transfer"
    it "uses snake_case object_type for deleted_items lookup" do
      id = SecureRandom.uuid
      DB[:deleted_items].insert(
        workspace_id: workspace[:id],
        object_type: "settlement_transfer",
        object_id: id,
        deleted_at: Time.now
      )

      result = SettlementTransfer.find_result(id)

      expect(result.failure?).to be true
      expect(result.failure.http_status).to eq(410)
      expect(result.failure.message).to eq("Settlement transfer not found")
    end

    it "uses downcased multi-word label in not_found message" do
      result = SettlementTransfer.find_result(SecureRandom.uuid)

      expect(result.failure?).to be true
      expect(result.failure.http_status).to eq(404)
      expect(result.failure.message).to eq("Settlement transfer not found")
    end
  end
end
