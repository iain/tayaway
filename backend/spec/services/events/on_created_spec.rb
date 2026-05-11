# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::OnCreated do
  describe ".call" do
    def event_with_actor_and_others(other_count: 1)
      workspace = TestFactories.workspace
      actor = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: actor)
      others = Array.new(other_count) do
        u = TestFactories.user
        TestFactories.workspace_membership(workspace: workspace, user: u)
        u
      end
      event = TestFactories.event(workspace: workspace, user: actor)
      [Event.find(event[:id]), actor, others]
    end

    it "lands a notification row for every workspace member except the actor" do
      event, actor, others = event_with_actor_and_others(other_count: 2)

      described_class.call(event: event, actor_user_id: actor[:id])

      recipient_ids = DB[:notifications].where(kind: "event_created").select_map(:user_id)
      expect(recipient_ids).to match_array(others.map { |u| u[:id] })
    end

    it "is silent when the actor is the only workspace member" do
      workspace = TestFactories.workspace
      actor = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: actor)
      event = Event.find(TestFactories.event(workspace: workspace, user: actor)[:id])

      described_class.call(event: event, actor_user_id: actor[:id])

      expect(DB[:notifications].where(kind: "event_created").count).to eq(0)
    end

    it "carries the event and workspace names in the payload so the bell can render them" do
      workspace = TestFactories.workspace
      actor = TestFactories.user
      other = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: actor)
      TestFactories.workspace_membership(workspace: workspace, user: other)
      DB[:workspaces].where(id: workspace[:id]).update(name: "Holiday Crew")
      event = TestFactories.event(workspace: workspace, user: actor, name: "Beach Trip")

      described_class.call(event: Event.find(event[:id]), actor_user_id: actor[:id])

      data = DB[:notifications].where(user_id: other[:id], kind: "event_created").get(:data)
      expect(data["title"]).to include("Beach Trip")
      expect(data["body"]).to include("Holiday Crew")
    end

    it "stays silent when notification dispatch raises (failure isolation)" do
      event, actor, = event_with_actor_and_others(other_count: 1)
      allow(Notifications::Dispatch).to receive(:call).and_raise(StandardError, "boom")
      stub_const("APP_ENV", "production") # Safely re-raises in test by default

      expect do
        described_class.call(event: event, actor_user_id: actor[:id])
      end.not_to raise_error
    end
  end
end
