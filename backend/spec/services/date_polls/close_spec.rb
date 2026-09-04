# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::Close do
  let(:workspace) { TestFactories.workspace }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
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
    expect(result.failure.message).to eq("not_event_owner")
  end

  it "lets a workspace admin close a poll on an event they don't own" do
    owner = TestFactories.user
    admin = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    admin_row = TestFactories.workspace_membership(workspace: workspace, user: admin, role: "admin")

    result = described_class.call(
      event_id: event[:id],
      membership: WorkspaceMembership.find(admin_row[:id]),
      selected_date_range_id: date_range[:id]
    )

    expect(result.success?).to be true
    expect(DatePoll.find(date_poll[:id]).selected_date_range_id.to_s).to eq(date_range[:id].to_s)
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
    expect(result.failure.message).to eq("already_resolved")
  end

  it "returns failure when selected_date_range_id is missing" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_range(date_poll: TestFactories.date_poll(event: event))

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
    TestFactories.date_range(date_poll: TestFactories.date_poll(event: event1))
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

  it "marks yes-voters on the winning date range as going" do
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
    rows = DB[:attendances].where(event_id: event[:id]).all
    expect(rows.length).to eq(2)
    expect(rows.map { |r| r[:user_id] }).to contain_exactly(voter1[:id], voter3[:id])
    expect(rows.all? { |r| r[:status] == "going" }).to be true

    attendance_objects = result.value![:objects].select { |o| o[:objectType] == "attendance" }
    expect(attendance_objects.length).to eq(2)
  end

  it "flips a pre-existing declined attendance back to going without duplicating the row" do
    owner = TestFactories.user
    voter = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    TestFactories.vote(user: voter, date_range: date_range, response: "yes")
    # The voter answered "not going" before the poll closed; their yes vote
    # on the winning range flips the same row back to going.
    declined_row = TestFactories.attendance(event: event, user: voter, status: "declined")

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(owner),
      selected_date_range_id: date_range[:id]
    )

    expect(result.success?).to be true
    row = DB[:attendances].where(id: declined_row[:id]).first
    expect(row[:status]).to eq("going")
    expect(row[:days]).to be_nil
    expect(DB[:attendances].where(event_id: event[:id]).count).to eq(1)
  end

  it "keeps an existing attendance's day set" do
    owner = TestFactories.user
    voter = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    # Polls can run on already-dated events, so the voter may have answered
    # with a partial day set before the poll closed. Close must keep that
    # day set instead of widening to whole-event.
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    picked = [Date.today + 1, Date.today + 2].map(&:iso8601)
    TestFactories.attendance(event: event, user: voter, days: picked)
    TestFactories.vote(user: voter, date_range: date_range, response: "yes")

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(owner),
      selected_date_range_id: date_range[:id]
    )

    expect(result.success?).to be true
    row = DB[:attendances].where(event_id: event[:id], user_id: voter[:id]).first
    expect(row[:status]).to eq("going")
    expect(row[:days].to_a).to eq(picked)
  end

  it "resets non-voters' answers when closing changes the dates" do
    owner = TestFactories.user
    yes_voter = TestFactories.user
    bystander = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    # Poll opened on an already-dated event ("Open Date Poll Anyway"): the
    # winning range replaces the dates, so answers given for the old window
    # revert to pending — keep the people, clear the answers — except
    # yes-voters on the winner, whose vote is their new answer.
    DB[:events].where(id: event[:id]).update(start_date: Date.today + 30, end_date: Date.today + 32)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    TestFactories.vote(user: yes_voter, date_range: date_range, response: "yes")
    picked = [(Date.today + 1).iso8601]
    yes_row = TestFactories.attendance(event: event, user: yes_voter, days: picked)
    bystander_row = TestFactories.attendance(event: event, user: bystander, status: "going")
    guest = TestFactories.guest(workspace: workspace)
    guest_row = TestFactories.attendance(event: event, guest: guest, host: owner)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(owner),
      selected_date_range_id: date_range[:id]
    )

    expect(result.success?).to be true
    rows = DB[:attendances].where(event_id: event[:id]).all.to_h { |r| [r[:id], r] }
    expect(rows[bystander_row[:id]][:status]).to eq("pending")
    expect(rows[bystander_row[:id]][:days]).to be_nil
    expect(rows[guest_row[:id]][:status]).to eq("pending")
    expect(rows[yes_row[:id]][:status]).to eq("going")
    expect(rows[yes_row[:id]][:days].to_a).to eq(picked)
  end

  it "leaves answers alone when the poll sets dates for the first time" do
    owner = TestFactories.user
    bystander = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    bystander_row = TestFactories.attendance(event: event, user: bystander, status: "going")

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(owner),
      selected_date_range_id: date_range[:id]
    )

    expect(result.success?).to be true
    expect(DB[:attendances].where(id: bystander_row[:id]).get(:status)).to eq("going")
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

    it "sends the RSVP prompt to going members whose answer was reset" do
      owner = TestFactories.user
      voter = TestFactories.user(email: "voter@example.com")
      bystander = TestFactories.user(email: "bystander@example.com")
      event = TestFactories.event(workspace: workspace, user: owner)
      DB[:events].where(id: event[:id]).update(start_date: Date.today + 30, end_date: Date.today + 32)
      date_poll = TestFactories.date_poll(event: event)
      date_range = TestFactories.date_range(date_poll: date_poll)
      TestFactories.vote(user: voter, date_range: date_range, response: "yes")
      TestFactories.attendance(event: event, user: bystander, status: "going")

      described_class.call(
        event_id: event[:id],
        membership: membership_for(owner),
        selected_date_range_id: date_range[:id]
      )

      message = Mail::TestMailer.deliveries.find { |m| m.to.first == "bystander@example.com" }
      expect(message).not_to be_nil
      expect(message.text_part.body.to_s).to include("Head to the event page to RSVP")
    end

    # Failure-isolation for the notifier is exercised in
    # DatePolls::OnClosed's spec; here we trust that the wire-up calls
    # the handler and don't repeat the rescue assertion.
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
