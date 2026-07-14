# frozen_string_literal: true

require "spec_helper"

RSpec.describe GuestSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:guest_row) { TestFactories.guest(workspace: workspace) }
      let(:pool_object) { described_class.serialize_batch([Guest.find(guest_row[:id])], pool: nil).first }

      it_behaves_like "a pool object with createdAt", "guest"
    end

    it "serializes guest fields" do
      row = TestFactories.guest(workspace: workspace, name: "Emma", placeholder: true, created_by: user)

      result = described_class.serialize_batch([Guest.find(row[:id])], pool: nil).first

      expect(result[:workspaceId]).to eq(workspace[:id].to_s)
      expect(result[:name]).to eq("Emma")
      expect(result[:placeholder]).to be true
      expect(result[:createdByUserId]).to eq(user[:id].to_s)
    end
  end

  describe ".policy_context_batch" do
    it "flags guests referenced by attendance rows" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      referenced = TestFactories.guest(workspace: workspace)
      free = TestFactories.guest(workspace: workspace)
      TestFactories.attendance(event: event_row, guest: referenced, host: user, status: "declined")

      contexts = described_class.policy_context_batch([referenced, free].map { |r| Guest.find(r[:id]) })

      expect(contexts[referenced[:id]]).to eq({ has_attendances: true })
      expect(contexts[free[:id]]).to eq({ has_attendances: false })
    end
  end
end
