# frozen_string_literal: true

require "spec_helper"

RSpec.describe GuestPolicy do
  let(:workspace) { TestFactories.workspace }
  let(:membership) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace)[:id]) }
  let(:guest) { Guest.find(TestFactories.guest(workspace: workspace)[:id]) }

  it "lets any workspace member rename any guest" do
    policy = described_class.new(guest, membership: membership)
    expect(policy.rename).to be_success
  end

  it "lets a member delete a guest nothing references" do
    policy = described_class.new(guest, membership: membership)
    expect(policy.delete).to be_success
  end

  it "blocks deleting a guest with attendance rows — rename is the remedy" do
    policy = described_class.new(guest, membership: membership, has_attendances: true)
    expect(policy.delete).to be_failure
    expect(policy.delete.failure).to eq(:has_attendances)
  end

  it "has correct ACTIONS" do
    expect(described_class::ACTIONS).to contain_exactly(:rename, :delete)
  end
end
