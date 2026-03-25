# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe AuditLog do
  describe ".record" do
    let(:user) { TestFactories.user }
    let(:workspace) { TestFactories.workspace }

    it "inserts a row into audit_logs" do
      object_id = SecureRandom.uuid

      expect {
        described_class.record(
          user_id: user[:id],
          action: "create",
          object_type: "event",
          object_id: object_id,
          workspace_id: workspace[:id]
        )
      }.to change { DB[:audit_logs].count }.by(1)

      row = DB[:audit_logs].order(:created_at).last
      expect(row[:user_id]).to eq(user[:id])
      expect(row[:action]).to eq("create")
      expect(row[:object_type]).to eq("event")
      expect(row[:object_id]).to eq(object_id)
      expect(row[:workspace_id]).to eq(workspace[:id])
      expect(row[:metadata]).to be_nil
    end

    it "records metadata as JSONB" do
      object_id = SecureRandom.uuid

      described_class.record(
        user_id: user[:id],
        action: "update",
        object_type: "expense",
        object_id: object_id,
        workspace_id: workspace[:id],
        metadata: { "changed_fields" => ["amount"] }
      )

      row = DB[:audit_logs].order(:created_at).last
      expect(row[:metadata].to_h).to include("changed_fields" => ["amount"])
    end

    it "allows nil user_id for system actions" do
      object_id = SecureRandom.uuid

      described_class.record(
        user_id: nil,
        action: "delete",
        object_type: "vote",
        object_id: object_id,
        workspace_id: nil
      )

      row = DB[:audit_logs].order(:created_at).last
      expect(row[:user_id]).to be_nil
      expect(row[:workspace_id]).to be_nil
    end

    it "does not raise on DB errors — logs and swallows" do
      allow(APP_LOGGER).to receive(:error)

      # Pass an invalid UUID to trigger a DB error
      expect {
        described_class.record(
          user_id: user[:id],
          action: "create",
          object_type: "event",
          object_id: "not-a-uuid",
          workspace_id: workspace[:id]
        )
      }.not_to raise_error
    end
  end
end
