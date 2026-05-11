# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::OnClosed do
  describe ".call" do
    let(:workspace) { TestFactories.workspace }
    let(:owner) { TestFactories.user }
    let(:yes_voter) { TestFactories.user(email: "yes@example.com") }
    let(:no_voter) { TestFactories.user(email: "no@example.com") }

    def closed_poll
      event = TestFactories.event(workspace: workspace, user: owner, name: "Summer Trip")
      poll = TestFactories.date_poll(event: event)
      range = TestFactories.date_range(date_poll: poll)
      TestFactories.vote(user: yes_voter, date_range: range, response: "yes")
      TestFactories.vote(user: no_voter, date_range: range, response: "no")
      [Event.find(event[:id]), DateRange.for_date_poll(poll[:id]).first]
    end

    it "notifies every voter (yes and no) across all ranges of the poll" do
      Mail::TestMailer.deliveries.clear
      event, date_range = closed_poll

      described_class.call(event: event, date_range: date_range, yes_voter_ids: [yes_voter[:id]])

      recipients = Mail::TestMailer.deliveries.map { |m| m.to.first }
      expect(recipients).to contain_exactly(yes_voter[:email], no_voter[:email])
    end

    it "carries auto_rsvped: true for yes-voters on the winning range" do
      event, date_range = closed_poll

      described_class.call(event: event, date_range: date_range, yes_voter_ids: [yes_voter[:id]])

      yes_text = Mail::TestMailer.deliveries.find { |m| m.to.first == yes_voter[:email] }.text_part.body.to_s
      no_text = Mail::TestMailer.deliveries.find { |m| m.to.first == no_voter[:email] }.text_part.body.to_s
      expect(yes_text).to include("You've been RSVPed")
      expect(no_text).to include("Head to the event page")
    end

    it "attaches an ICS file shaped from the winning date range" do
      event, date_range = closed_poll
      DB[:date_ranges].where(id: date_range.id).update(
        start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 5)
      )
      date_range = DateRange.for_date_poll(date_range.date_poll_id).first

      described_class.call(event: event, date_range: date_range, yes_voter_ids: [yes_voter[:id]])

      message = Mail::TestMailer.deliveries.first
      attachment = message.attachments.first
      expect(attachment.filename).to eq("summer-trip.ics")
      expect(attachment.body.to_s).to include("DTSTART;VALUE=DATE:20260601")
    end
  end
end
