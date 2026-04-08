# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::Delete do
  let(:workspace) { TestFactories.workspace }

  it "returns failure when user is not the owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    TestFactories.workspace_membership(workspace: workspace, user: owner)
    other_membership_row = TestFactories.workspace_membership(workspace: workspace, user: other_user)
    event = TestFactories.event(workspace: workspace, user: owner)
    membership = WorkspaceMembership.find(other_membership_row[:id])

    result = described_class.call(event_id: event[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to include("not_owner")
    expect(DB[:events].where(id: event[:id]).count).to eq(1)
  end

  it "deletes event when user is owner" do
    user = TestFactories.user
    membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
    event = TestFactories.event(workspace: workspace, user: user)
    membership = WorkspaceMembership.find(membership_row[:id])

    result = described_class.call(event_id: event[:id], membership: membership)

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "event", id: event[:id] }])
    expect(DB[:events].where(id: event[:id]).count).to eq(0)
  end

  it "logs info when event is deleted" do
    user = TestFactories.user
    membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
    event = TestFactories.event(workspace: workspace, user: user)
    membership = WorkspaceMembership.find(membership_row[:id])
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(event_id: event[:id], membership: membership)

    expect(logged_messages).to include(a_string_including("[Events::Delete]"))
  end
end
