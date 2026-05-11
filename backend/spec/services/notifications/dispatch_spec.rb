# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Dispatch do
  before { Mail::TestMailer.deliveries.clear }

  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:poll_closed_data) do
    {
      email: user[:email],
      user_name: "Test",
      event_name: "Trip",
      date_label: "Aug 1",
      event_url: "https://e",
      ics_content: "BEGIN:VCALENDAR\nEND:VCALENDAR\n",
      ics_filename: "trip.ics",
      auto_rsvped: false
    }
  end

  describe ".call" do
    it "delivers via the kind's default channels when no preferences are stored" do
      described_class.call(
        kind: :poll_closed,
        user_id: user[:id],
        workspace_id: workspace[:id],
        data: poll_closed_data
      )

      expect(Mail::TestMailer.deliveries.length).to eq(1)
      expect(Mail::TestMailer.deliveries.first.to).to eq([user[:email]])
    end

    it "writes an in-app notification row alongside the email" do
      described_class.call(
        kind: :poll_closed,
        user_id: user[:id],
        workspace_id: workspace[:id],
        data: poll_closed_data
      )

      row = DB[:notifications].where(user_id: user[:id]).first
      expect(row).not_to be_nil
      expect(row[:kind]).to eq("poll_closed")
      expect(row[:data]["title"]).to eq("Dates confirmed: Trip")
      expect(row[:data]["body"]).to eq("Aug 1")
    end

    it "skips user-bound channels when no user_id is supplied" do
      described_class.call(
        kind: :workspace_invite,
        data: {
          email: "stranger@example.com",
          invite_link: "https://i",
          workspace_name: "WS",
          name: nil
        }
      )

      expect(Mail::TestMailer.deliveries.length).to eq(1)
      expect(DB[:notifications].count).to eq(0)
    end

    it "skips a default channel the user has disabled" do
      DB[:user_notification_preferences].insert(
        user_id: user[:id],
        kind: "poll_closed",
        channel: "email",
        enabled: false
      )

      described_class.call(
        kind: :poll_closed,
        user_id: user[:id],
        workspace_id: workspace[:id],
        data: poll_closed_data
      )

      expect(Mail::TestMailer.deliveries).to be_empty
      expect(DB[:notifications].count).to eq(1) # in_app still fires
    end

    it "treats other users' preferences as irrelevant" do
      other = TestFactories.user
      DB[:user_notification_preferences].insert(
        user_id: other[:id],
        kind: "poll_closed",
        channel: "email",
        enabled: false
      )

      described_class.call(
        kind: :poll_closed,
        user_id: user[:id],
        workspace_id: workspace[:id],
        data: poll_closed_data
      )

      expect(Mail::TestMailer.deliveries.length).to eq(1)
    end

    it "raises for an unknown kind" do
      expect {
        described_class.call(kind: :totally_made_up, data: {})
      }.to raise_error(KeyError)
    end
  end
end
