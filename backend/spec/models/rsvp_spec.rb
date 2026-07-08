# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsvp do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:event_row) { TestFactories.event(workspace: workspace, user: user) }

  before do
    TestFactories.workspace_membership(workspace: workspace, user: user)
    DB[:events].where(id: event_row[:id]).update(start_date: Date.today, end_date: Date.today + 3)
  end

  def find_rsvp(attendance)
    row = TestFactories.rsvp(event: event_row, user: user, attending: true, attendance: attendance)
    Rsvp.find(row[:id])
  end

  describe "#attendance parsing" do
    it "reads a legacy flat ISO-string day set as guest-free days" do
      rsvp = find_rsvp([Date.today + 1, Date.today + 2])

      expect(rsvp.attendance).to eq(
        [{ date: Date.today + 1, plus_ones: 0 }, { date: Date.today + 2, plus_ones: 0 }]
      )
    end

    it "reads per-day plus-ones from the object shape" do
      rsvp = find_rsvp([
                         { "date" => (Date.today + 1).iso8601, "plusOnes" => 3 },
                         Date.today + 2
                       ]
                      )

      expect(rsvp.attendance).to eq(
        [{ date: Date.today + 1, plus_ones: 3 }, { date: Date.today + 2, plus_ones: 0 }]
      )
    end
  end

  describe "#effective_attendance" do
    it "expands a whole-event RSVP to every event day, guest-free" do
      row = TestFactories.rsvp(event: event_row, user: user, attending: true, attendance: nil)
      rsvp = described_class.find(row[:id])
      event = Event.find(event_row[:id])

      expect(rsvp.effective_attendance(event)).to eq(
        (Date.today..(Date.today + 3)).map { |date| { date: date, plus_ones: 0 } }
      )
    end

    it "carries the day set's guests, and effective_dates drops them" do
      rsvp = find_rsvp([{ "date" => (Date.today + 1).iso8601, "plusOnes" => 2 }])
      event = Event.find(event_row[:id])

      expect(rsvp.effective_attendance(event)).to eq([{ date: Date.today + 1, plus_ones: 2 }])
      expect(rsvp.effective_dates(event)).to eq([Date.today + 1])
    end
  end
end
