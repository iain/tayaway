# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::Close do
  let(:workspace) { TestFactories.workspace }

  def membership_for(u)
    row = TestFactories.workspace_membership(workspace: workspace, user: u)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when user is not the event owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(other_user),
      selected_date_range_id: date_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("not_owner")
  end

  it "returns failure when poll is already resolved" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event, closed_at: Time.now)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      selected_date_range_id: date_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is already resolved")
  end

  it "returns failure when selected_date_range_id is missing" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      selected_date_range_id: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("selected_date_range_id is required")
  end

  it "returns failure when date range does not belong to poll" do
    user = TestFactories.user
    event1 = TestFactories.event(workspace: workspace, user: user)
    event2 = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event1)
    other_poll = TestFactories.date_poll(event: event2)
    other_range = TestFactories.date_range(date_poll: other_poll)

    result = described_class.call(
      event_id: event1[:id],
      membership: membership_for(user),
      selected_date_range_id: other_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Date range does not belong to this poll")
  end

  it "closes the poll and sets the winner" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      selected_date_range_id: date_range[:id]
    )

    expect(result.success?).to be true
    poll = result.value![:objects].find { |o| o[:objectType] == "datePoll" }
    expect(poll[:status]).to eq("resolved")
    expect(poll[:selectedDateRangeId]).to eq(date_range[:id])

    db_poll = DB[:date_polls].where(id: date_poll[:id]).first
    expect(db_poll[:closed_at]).not_to be_nil
    expect(db_poll[:selected_date_range_id]).to eq(date_range[:id])
  end

  it "auto-RSVPs yes-voters on the winning date range" do
    owner = TestFactories.user
    voter1 = TestFactories.user
    voter2 = TestFactories.user
    voter3 = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    TestFactories.vote(user: voter1, date_range: date_range, response: "yes")
    TestFactories.vote(user: voter2, date_range: date_range, response: "no")
    TestFactories.vote(user: voter3, date_range: date_range, response: "yes")

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(owner),
      selected_date_range_id: date_range[:id]
    )

    expect(result.success?).to be true
    rsvps = DB[:rsvps].where(event_id: event[:id]).all
    expect(rsvps.length).to eq(2)
    expect(rsvps.map { |r| r[:user_id] }).to contain_exactly(voter1[:id], voter3[:id])
    expect(rsvps.all? { |r| r[:attending] == true }).to be true

    # RSVP objects should be in the response
    rsvp_objects = result.value![:objects].select { |o| o[:objectType] == "rsvp" }
    expect(rsvp_objects.length).to eq(2)
  end

  it "does not raise a unique constraint violation when a yes-voter already has an RSVP" do
    owner = TestFactories.user
    voter = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    TestFactories.vote(user: voter, date_range: date_range, response: "yes")
    # Voter already has a pre-existing RSVP (e.g. set manually before the poll closed)
    TestFactories.rsvp(event: event, user: voter, attending: false)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(owner),
      selected_date_range_id: date_range[:id]
    )

    expect(result.success?).to be true
    rsvps = DB[:rsvps].where(event_id: event[:id], user_id: voter[:id]).all
    # No duplicate RSVP should have been created
    expect(rsvps.length).to eq(1)
    # Existing RSVP should be updated to attending: true
    expect(rsvps.first[:attending]).to be true
  end

  describe "poll closed emails" do
    before { Mail::TestMailer.deliveries.clear }

    it "sends emails to all voters across all date ranges" do
      owner = TestFactories.user(name: "Owner")
      voter1 = TestFactories.user(name: "Voter One", email: "voter1@example.com")
      voter2 = TestFactories.user(name: "Voter Two", email: "voter2@example.com")
      voter3 = TestFactories.user(name: "Voter Three", email: "voter3@example.com")
      event = TestFactories.event(workspace: workspace, user: owner, name: "Beach Trip")
      date_poll = TestFactories.date_poll(event: event)
      winning_range = TestFactories.date_range(date_poll: date_poll, start_date: Date.new(2026, 3, 10), end_date: Date.new(2026, 3, 12))
      other_range = TestFactories.date_range(date_poll: date_poll, start_date: Date.new(2026, 4, 1), end_date: Date.new(2026, 4, 3))

      TestFactories.vote(user: voter1, date_range: winning_range, response: "yes")
      TestFactories.vote(user: voter2, date_range: winning_range, response: "no")
      TestFactories.vote(user: voter3, date_range: other_range, response: "yes")

      described_class.call(
        event_id: event[:id],
        membership: membership_for(owner),
        selected_date_range_id: winning_range[:id]
      )

      recipients = Mail::TestMailer.deliveries.map { |m| m.to.first }
      expect(recipients).to contain_exactly("voter1@example.com", "voter2@example.com", "voter3@example.com")
    end

    it "includes ICS attachment with event details" do
      owner = TestFactories.user
      voter = TestFactories.user(email: "voter@example.com")
      event = TestFactories.event(workspace: workspace, user: owner, name: "Summer Trip")
      date_poll = TestFactories.date_poll(event: event)
      date_range = TestFactories.date_range(date_poll: date_poll, start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 5))

      TestFactories.vote(user: voter, date_range: date_range, response: "yes")

      described_class.call(
        event_id: event[:id],
        membership: membership_for(owner),
        selected_date_range_id: date_range[:id]
      )

      message = Mail::TestMailer.deliveries.first
      expect(message.attachments.length).to eq(1)
      attachment = message.attachments.first
      expect(attachment.filename).to eq("summer-trip.ics")
      ics_content = attachment.body.to_s
      expect(ics_content).to include("BEGIN:VCALENDAR")
      expect(ics_content).to include("SUMMARY:Summer Trip")
      expect(ics_content).to include("DTSTART;VALUE=DATE:20260601")
    end

    it "sends auto-RSVPed messaging to yes-voters on the winning range" do
      owner = TestFactories.user
      yes_voter = TestFactories.user(email: "yes@example.com")
      event = TestFactories.event(workspace: workspace, user: owner)
      date_poll = TestFactories.date_poll(event: event)
      date_range = TestFactories.date_range(date_poll: date_poll)

      TestFactories.vote(user: yes_voter, date_range: date_range, response: "yes")

      described_class.call(
        event_id: event[:id],
        membership: membership_for(owner),
        selected_date_range_id: date_range[:id]
      )

      message = Mail::TestMailer.deliveries.find { |m| m.to.first == "yes@example.com" }
      text_body = message.text_part.body.to_s
      expect(text_body).to include("You've been RSVPed as attending based on your vote.")
    end

    it "sends RSVP prompt to voters who were not auto-RSVPed" do
      owner = TestFactories.user
      no_voter = TestFactories.user(email: "no@example.com")
      event = TestFactories.event(workspace: workspace, user: owner)
      date_poll = TestFactories.date_poll(event: event)
      date_range = TestFactories.date_range(date_poll: date_poll)

      TestFactories.vote(user: no_voter, date_range: date_range, response: "no")

      described_class.call(
        event_id: event[:id],
        membership: membership_for(owner),
        selected_date_range_id: date_range[:id]
      )

      message = Mail::TestMailer.deliveries.find { |m| m.to.first == "no@example.com" }
      text_body = message.text_part.body.to_s
      expect(text_body).to include("Head to the event page to RSVP")
    end

    it "does not break the API response if email sending fails" do
      owner = TestFactories.user
      voter = TestFactories.user
      event = TestFactories.event(workspace: workspace, user: owner)
      date_poll = TestFactories.date_poll(event: event)
      date_range = TestFactories.date_range(date_poll: date_poll)

      TestFactories.vote(user: voter, date_range: date_range, response: "yes")

      allow(Mailers::PollClosed).to receive(:send_email).and_raise(StandardError, "SMTP down")

      result = described_class.call(
        event_id: event[:id],
        membership: membership_for(owner),
        selected_date_range_id: date_range[:id]
      )

      expect(result.success?).to be true
    end
  end

  it "logs info when poll is closed" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      selected_date_range_id: date_range[:id]
    )

    expect(logged_messages).to include(a_string_including("[DatePolls::Close]"))
  end
end
