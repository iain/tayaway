# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::Delete do
  it "returns failure when user is not the owner" do
    owner = create(:user)
    other_user = create(:user)
    event = create(:event, user: owner)

    result = described_class.call(event: event, current_user_id: other_user.id)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
    expect(Event.where(id: event.id).count).to eq(1)
  end

  it "deletes event when user is owner" do
    user = create(:user)
    event = create(:event, user: user)

    result = described_class.call(event: event, current_user_id: user.id)

    expect(result.success?).to be true
    expect(result.value![:message]).to eq("Event deleted successfully")
    expect(Event.where(id: event.id).count).to eq(0)
  end
end
