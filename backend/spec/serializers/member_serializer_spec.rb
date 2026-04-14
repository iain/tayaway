# frozen_string_literal: true

require "spec_helper"

RSpec.describe MemberSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      let(:membership_row) { TestFactories.workspace_membership(workspace: workspace, user: user) }
      let(:pool_object) { described_class.serialize_batch([WorkspaceMembership.find(membership_row[:id])], pool: nil).first }

      subject { pool_object }

      it_behaves_like "a pool object with createdAt", "member"
    end

    it "returns an empty array for empty input" do
      expect(described_class.serialize_batch([], pool: nil)).to eq([])
    end

    it "combines user and membership fields into a member hash" do
      DB[:users].where(id: user[:id]).update(
        phone_number: "+31612345678",
        location_name: "Amsterdam"
      )
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user, role: "admin")
      membership = WorkspaceMembership.find(membership_row[:id])

      result = described_class.serialize_batch([membership], pool: nil).first

      expect(result[:id]).to eq(membership.id.to_s)
      expect(result[:objectType]).to eq("member")
      expect(result[:workspaceId]).to eq(workspace[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:email]).to eq(user[:email])
      expect(result[:phoneNumber]).to eq("+31612345678")
      expect(result[:locationName]).to eq("Amsterdam")
      expect(result[:role]).to eq("admin")
      expect(result[:hasIban]).to be false
    end

    it "sets hasIban: true when the user has an iban" do
      DB[:users].where(id: user[:id]).update(iban: Encryption.encrypt("NL91ABNA0417164300"))
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
      membership = WorkspaceMembership.find(membership_row[:id])

      result = described_class.serialize_batch([membership], pool: nil).first

      expect(result[:hasIban]).to be true
    end

    it "never emits the raw iban" do
      DB[:users].where(id: user[:id]).update(iban: Encryption.encrypt("NL91ABNA0417164300"))
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
      membership = WorkspaceMembership.find(membership_row[:id])

      result = described_class.serialize_batch([membership], pool: nil).first

      expect(result).not_to have_key(:iban)
    end

    it "returns nil for memberships whose user row is missing" do
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
      membership = WorkspaceMembership.find(membership_row[:id])
      DB[:users].where(id: user[:id]).delete

      result = described_class.serialize_batch([membership], pool: nil)

      expect(result).to eq([nil])
    end

    it "uses the max of user.updated_at and membership.updated_at for updatedAt" do
      # Triggers fire on UPDATE but not INSERT, so we insert a user with a
      # future updated_at directly to verify the max picks the user timestamp.
      future = Time.now + 3600
      user_id = SecureRandom.uuid
      DB[:users].insert(
        id: user_id,
        email: "ts-test-#{user_id}@example.com",
        created_at: Time.now,
        updated_at: future
      )
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: { id: user_id })
      membership = WorkspaceMembership.find(membership_row[:id])

      result = described_class.serialize_batch([membership], pool: nil).first

      expect(Time.iso8601(result[:updatedAt])).to be_within(1).of(future)
    end
  end
end
