# frozen_string_literal: true

require "spec_helper"

RSpec.describe RsvpSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe ".serialize_batch" do
    it "serializes rsvp fields" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      rsvp_row = TestFactories.rsvp(
        event: event_row, user: user, attending: true,
        start_date: Date.today, end_date: Date.today + 2
      )
      rsvp = Rsvp.find(rsvp_row[:id])

      result = described_class.serialize_batch([rsvp], pool: nil).first

      expect(result[:id]).to eq(rsvp.id.to_s)
      expect(result[:objectType]).to eq("rsvp")
      expect(result[:eventId]).to eq(event_row[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:attending]).to be true
      expect(result[:startDate]).to eq(Date.today.iso8601)
      expect(result[:endDate]).to eq((Date.today + 2).iso8601)
    end

    it "handles nil dates" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      rsvp_row = TestFactories.rsvp(event: event_row, user: user, attending: false)
      DB[:rsvps].where(id: rsvp_row[:id]).update(start_date: nil, end_date: nil)
      rsvp = Rsvp.find(rsvp_row[:id])

      result = described_class.serialize_batch([rsvp], pool: nil).first

      expect(result[:startDate]).to be_nil
      expect(result[:endDate]).to be_nil
    end
  end
end
