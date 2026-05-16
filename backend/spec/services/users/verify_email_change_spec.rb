# frozen_string_literal: true

require "spec_helper"

RSpec.describe Users::VerifyEmailChange do
  it "rejects nil, invalid, and expired JWTs" do
    nil_result = described_class.call(token: nil)
    expect(nil_result.failure?).to be true
    expect(nil_result.failure.message).to eq("Token is required")

    invalid_result = described_class.call(token: "not-a-jwt")
    expect(invalid_result.failure?).to be true
    expect(invalid_result.failure.http_status).to eq(401)

    expired_jwt = JWT.encode({ token: "t", email: "e@e.com", exp: (Time.now - 60).to_i }, APP_CONFIG.app_secret, "HS256")
    expired_result = described_class.call(token: expired_jwt)
    expect(expired_result.failure?).to be true
    expect(expired_result.failure.message).to eq("Invalid or expired verification link")
  end

  it "rejects non-existent, used, and expired tokens" do
    user = TestFactories.user(email: "old@example.com")

    # Non-existent token in DB
    fake_jwt = Auth::Token.encode_email_change(token: "nonexistent", email: "new@example.com")
    expect(described_class.call(token: fake_jwt).failure?).to be true

    # Already-used token
    used = TestFactories.email_change_token(user: user, new_email: "used@example.com", used_at: Time.now)
    used_jwt = Auth::Token.encode_email_change(token: used.token, email: "used@example.com")
    expect(described_class.call(token: used_jwt).failure?).to be true

    # Expired token
    expired = TestFactories.email_change_token(user: user, new_email: "expired@example.com", expires_at: Time.now - 60)
    expired_jwt = Auth::Token.encode_email_change(token: expired.token, email: "expired@example.com")
    expect(described_class.call(token: expired_jwt).failure?).to be true
  end

  it "rejects when new email was taken (race condition) or user email already changed" do
    user = TestFactories.user(email: "old@example.com")
    TestFactories.user(email: "taken@example.com")

    # Race condition: email taken between request and verify
    taken_token = TestFactories.email_change_token(user: user, new_email: "taken@example.com")
    taken_jwt = Auth::Token.encode_email_change(token: taken_token.token, email: "taken@example.com")
    taken_result = described_class.call(token: taken_jwt)
    expect(taken_result.failure?).to be true
    expect(taken_result.failure.message).to include("already in use")

    # User's email changed since token was created
    changed_token = TestFactories.email_change_token(user: user, email: "old@example.com", new_email: "new@example.com")
    DB[:users].where(id: user[:id]).update(email: "different@example.com")
    changed_jwt = Auth::Token.encode_email_change(token: changed_token.token, email: "new@example.com")
    changed_result = described_class.call(token: changed_jwt)
    expect(changed_result.failure?).to be true
    expect(changed_result.failure.message).to include("already been changed")
  end

  it "updates email, marks token used, and broadcasts to all workspaces" do
    user = TestFactories.user(email: "old@example.com")
    workspace1 = TestFactories.workspace
    workspace2 = TestFactories.workspace
    TestFactories.workspace_membership(workspace: workspace1, user: user)
    TestFactories.workspace_membership(workspace: workspace2, user: user)

    allow(Broadcaster).to receive(:object_changed)

    email_token = TestFactories.email_change_token(user: user, email: "old@example.com", new_email: "new@example.com")
    jwt = Auth::Token.encode_email_change(token: email_token.token, email: "new@example.com")

    result = described_class.call(token: jwt)

    expect(result.success?).to be true
    expect(result.value![:message]).to include("email has been updated")
    expect(DB[:users].where(id: user[:id]).first[:email]).to eq("new@example.com")
    expect(DB[:email_change_tokens].where(id: email_token.record.id.to_s).first[:used_at]).not_to be_nil
    # Two `member` broadcasts — one per workspace the user belongs to —
    # plus one `notification` broadcast for the in-app delivery of
    # `email_change_completed` to the user.
    expect(Broadcaster).to have_received(:object_changed).with("member", anything).twice
    expect(Broadcaster).to have_received(:object_changed).with("notification", anything).once
  end
end
