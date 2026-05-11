# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::OnDetailsChanged do
  describe ".call" do
    let(:workspace) { TestFactories.workspace }
    let(:owner) { TestFactories.user }
    let(:attendee) { TestFactories.user }

    before do
      TestFactories.workspace_membership(workspace: workspace, user: owner)
      TestFactories.workspace_membership(workspace: workspace, user: attendee)
    end

    def stored_event(start_date:, end_date: start_date, location_name: nil)
      row = TestFactories.event(workspace: workspace, user: owner)
      DB[:events].where(id: row[:id]).update(
        start_date: start_date, end_date: end_date, location_name: location_name
      )
      Event.find(row[:id])
    end

    it "notifies attending users when dates move" do
      before_event = stored_event(start_date: Date.new(2026, 3, 1))
      after_event = before_event.with(start_date: Date.new(2026, 4, 1), end_date: Date.new(2026, 4, 1))
      TestFactories.rsvp(event: { id: before_event.id }, user: attendee, attending: true)

      described_class.call(before: before_event, after: after_event, actor_user_id: owner[:id])

      rows = DB[:notifications].where(user_id: attendee[:id], kind: "event_details_changed").all
      expect(rows.length).to eq(1)
      expect(rows.first[:data]["body"]).to eq("New dates")
    end

    it "is silent when only the name changed" do
      before_event = stored_event(start_date: Date.new(2026, 3, 1))
      after_event = before_event.with(name: "Renamed")
      TestFactories.rsvp(event: { id: before_event.id }, user: attendee, attending: true)

      described_class.call(before: before_event, after: after_event, actor_user_id: owner[:id])

      expect(DB[:notifications].where(kind: "event_details_changed").count).to eq(0)
    end

    it "summarises combined date and location changes" do
      before_event = stored_event(start_date: Date.new(2026, 3, 1), location_name: "Old Place")
      after_event = before_event.with(
        start_date: Date.new(2026, 4, 1),
        end_date: Date.new(2026, 4, 1),
        location_name: "New Place"
      )
      TestFactories.rsvp(event: { id: before_event.id }, user: attendee, attending: true)

      described_class.call(before: before_event, after: after_event, actor_user_id: owner[:id])

      data = DB[:notifications].where(user_id: attendee[:id], kind: "event_details_changed").get(:data)
      expect(data["body"]).to eq("New dates and new location")
    end
  end
end
