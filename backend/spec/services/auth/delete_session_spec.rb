# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::DeleteSession do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }

  it "deletes the session and returns success" do
    session_id = session[:id]

    result = described_class.call(session_id: session_id, user_id: UUID.new(user[:id]))

    expect(result.success?).to be true
    expect(result.value![:message]).to eq("Session ended successfully")
    expect(DB[:sessions].where(id: session_id).count).to eq(0)
  end

  it "returns failure when session does not exist" do
    result = described_class.call(session_id: SecureRandom.uuid, user_id: UUID.new(user[:id]))

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Session not found")
    expect(result.failure.http_status).to eq(404)
  end

  it "returns failure when session belongs to another user" do
    other_user = TestFactories.user
    other_session = TestFactories.session(user: other_user)

    result = described_class.call(session_id: other_session[:id], user_id: UUID.new(user[:id]))

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Cannot delete another user's session")
    expect(result.failure.http_status).to eq(403)
  end

  it "returns failure when session is expired" do
    expired_session = TestFactories.session(user: user, expires_at: Time.now - 3600)

    result = described_class.call(session_id: expired_session[:id], user_id: UUID.new(user[:id]))

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Session not found")
  end
end
