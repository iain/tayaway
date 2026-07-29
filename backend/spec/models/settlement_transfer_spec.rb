# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementTransfer do
  # All transfers of a settlement are inserted in one transaction and share
  # the same created_at, so ordering needs the id tiebreaker to be stable.
  it "orders transfers with identical created_at by id" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)

    settlement_id = SecureRandom.uuid
    now = Time.now
    DB[:settlements].insert(
      id: settlement_id,
      event_id: event[:id],
      user_id: user[:id],
      created_at: now,
      updated_at: now
    )

    ids = Array.new(3) { SecureRandom.uuid }.sort
    ids.reverse_each do |id|
      DB[:settlement_transfers].insert(
        id: id,
        settlement_id: settlement_id,
        from_user_id: user[:id],
        to_user_id: nil,
        amount: 10.0,
        created_at: now,
        updated_at: now
      )
    end

    expect(described_class.for_settlement(settlement_id).map { |t| t.id.to_s }).to eq(ids)
    expect(described_class.ids_for_settlement(settlement_id)).to eq(ids)
  end
end
