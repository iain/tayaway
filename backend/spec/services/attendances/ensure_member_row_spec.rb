# frozen_string_literal: true

require "spec_helper"

RSpec.describe Attendances::EnsureMemberRow do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:actor) { TestFactories.user(name: "Actor") }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  before do
    TestFactories.workspace_membership(workspace: workspace, user: user)
  end

  it "returns the existing attendance row untouched" do
    existing = TestFactories.attendance(event: event, user: user, status: "declined")

    result = described_class.call(event: Event.find(event[:id]), user_id: user[:id].to_s, created_by_user_id: actor[:id].to_s)

    expect(result.success?).to be true
    expect(result.value!.id.to_s).to eq(existing[:id].to_s)
    expect(result.value!.status).to eq("declined")
  end

  it "creates a pending row when the member has none" do
    result = described_class.call(event: Event.find(event[:id]), user_id: user[:id].to_s, created_by_user_id: actor[:id].to_s)

    expect(result.success?).to be true
    attendance = result.value!
    expect(attendance.status).to eq("pending")
    expect(attendance.user_id.to_s).to eq(user[:id].to_s)
    expect(attendance.days).to be_nil
    expect(DB[:attendances].where(id: attendance.id.to_s).get(:created_by_user_id).to_s).to eq(actor[:id].to_s)
  end

  it "fails when the user is not a workspace member" do
    stranger = TestFactories.user

    result = described_class.call(event: Event.find(event[:id]), user_id: stranger[:id].to_s, created_by_user_id: actor[:id].to_s)

    expect(result.failure.message).to eq("User is not a member of this workspace")
    expect(DB[:attendances].where(event_id: event[:id]).count).to eq(0)
  end
end
