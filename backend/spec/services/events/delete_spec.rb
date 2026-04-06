# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::Delete do
  it "returns failure when user is not the owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(user: owner)

    result = described_class.call(event_id: event[:id], current_user_id: other_user[:id])

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
    expect(DB[:events].where(id: event[:id]).count).to eq(1)
  end

  it "deletes event when user is owner" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    event_id = event[:id]

    result = described_class.call(event_id: event[:id], current_user_id: user[:id])

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "event", id: event_id }])
    expect(DB[:events].where(id: event_id).count).to eq(0)
  end

  it "logs info when event is deleted" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(event_id: event[:id], current_user_id: user[:id])

    expect(logged_messages).to include(a_string_including("[Events::Delete]"))
  end
end
