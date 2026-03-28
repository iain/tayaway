# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::RevokeOtherSessions do
  let(:user) { TestFactories.user }
  let(:current_session) { TestFactories.session(user: user) }

  it "deletes all other sessions and returns success" do
    other1 = TestFactories.session(user: user)
    other2 = TestFactories.session(user: user)

    result = described_class.call(user_id: UUID.new(user[:id]), current_session_id: UUID.new(current_session[:id]))

    expect(result.success?).to be true
    expect(result.value![:message]).to eq("All other sessions have been revoked")
    expect(DB[:sessions].where(id: other1[:id]).count).to eq(0)
    expect(DB[:sessions].where(id: other2[:id]).count).to eq(0)
  end

  it "does not delete the current session" do
    TestFactories.session(user: user)

    described_class.call(user_id: UUID.new(user[:id]), current_session_id: UUID.new(current_session[:id]))

    expect(DB[:sessions].where(id: current_session[:id]).count).to eq(1)
  end

  it "does not delete sessions belonging to other users" do
    other_user = TestFactories.user
    other_user_session = TestFactories.session(user: other_user)

    described_class.call(user_id: UUID.new(user[:id]), current_session_id: UUID.new(current_session[:id]))

    expect(DB[:sessions].where(id: other_user_session[:id]).count).to eq(1)
  end

  it "succeeds even when there are no other sessions" do
    result = described_class.call(user_id: UUID.new(user[:id]), current_session_id: UUID.new(current_session[:id]))

    expect(result.success?).to be true
  end
end
