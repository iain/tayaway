# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosterPolicy do
  let(:creator) { TestFactories.user }
  let(:other_user) { TestFactories.user(email: "other@example.com") }
  let(:workspace) { TestFactories.workspace }
  let(:event_row) { TestFactories.event(workspace: workspace, user: creator) }

  let(:roster_row) do
    id = SecureRandom.uuid
    now = Time.now
    DB[:chore_rosters].insert(id: id, event_id: event_row[:id], user_id: creator[:id], created_at: now, updated_at: now)
    DB[:chore_rosters].where(id: id).first
  end
  let(:roster) { ChoreRoster.find(roster_row[:id]) }

  describe "#abilities" do
    it "allows delete for the creator" do
      abilities = described_class.new(roster: roster, user_id: creator[:id].to_s).abilities
      expect(abilities[:delete]).to be_a(BasePolicy::Allowed)
    end

    it "denies delete for other users" do
      abilities = described_class.new(roster: roster, user_id: other_user[:id].to_s).abilities
      expect(abilities[:delete]).to be_a(BasePolicy::Denied)
      expect(abilities[:delete].reason).to eq("not_creator")
    end
  end
end
