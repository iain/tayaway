# frozen_string_literal: true

require "spec_helper"

RSpec.describe Expenses::OnAdded do
  describe ".call" do
    let(:workspace) { TestFactories.workspace }
    let(:actor) { TestFactories.user }
    let(:attendee) { TestFactories.user }
    let(:event_row) { TestFactories.event(workspace: workspace, user: actor) }

    before do
      TestFactories.workspace_membership(workspace: workspace, user: actor)
      TestFactories.workspace_membership(workspace: workspace, user: attendee)
    end

    it "notifies attending RSVPs except the actor" do
      TestFactories.rsvp(event: event_row, user: actor, attending: true)
      TestFactories.rsvp(event: event_row, user: attendee, attending: true)

      described_class.call(
        event_id: event_row[:id],
        actor_user_id: actor[:id],
        description: "Pizza",
        amount: 12.5,
        workspace_id: workspace[:id]
      )

      recipient_ids = DB[:notifications].where(kind: "expense_added").select_map(:user_id)
      expect(recipient_ids).to contain_exactly(attendee[:id])
    end

    it "is silent when only the actor is attending" do
      TestFactories.rsvp(event: event_row, user: actor, attending: true)

      described_class.call(
        event_id: event_row[:id],
        actor_user_id: actor[:id],
        description: "Pizza",
        amount: 12.5,
        workspace_id: workspace[:id]
      )

      expect(DB[:notifications].where(kind: "expense_added").count).to eq(0)
    end

    it "is silent when the event is missing" do
      described_class.call(
        event_id: SecureRandom.uuid,
        actor_user_id: actor[:id],
        description: "Pizza",
        amount: 12.5,
        workspace_id: workspace[:id]
      )

      expect(DB[:notifications].count).to eq(0)
    end
  end
end
