# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::OnCanceled do
  describe ".call" do
    let(:workspace) { TestFactories.workspace }
    let(:owner) { TestFactories.user }
    let(:attendee) { TestFactories.user }
    let(:event) do
      Event.find(TestFactories.event(workspace: workspace, user: owner)[:id])
    end

    before do
      TestFactories.workspace_membership(workspace: workspace, user: owner)
      TestFactories.workspace_membership(workspace: workspace, user: attendee)
    end

    it "notifies attending users except the actor" do
      described_class.call(event: event, attending_user_ids: [owner[:id], attendee[:id]])

      recipient_ids = DB[:notifications].where(kind: "event_canceled").select_map(:user_id)
      expect(recipient_ids).to contain_exactly(attendee[:id])
    end

    it "is silent when nobody else was attending" do
      described_class.call(event: event, attending_user_ids: [owner[:id]])

      expect(DB[:notifications].where(kind: "event_canceled").count).to eq(0)
    end
  end
end
