# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Invites::Accept do
  let(:workspace) { TestFactories.workspace(name: "Test Workspace") }
  let(:inviter) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: inviter, role: "admin") }

  # rubocop:disable Sorbet/BlockMethodDefinition -- test helper used across examples
  def create_invite_with_token(email:)
    raw_token = SecureRandom.hex(32)
    token_hash = Auth::Token.digest(raw_token)
    now = Time.now
    id = SecureRandom.uuid

    DB[:workspace_invites].insert(
      id: id,
      workspace_id: workspace[:id],
      invited_by: inviter[:id],
      email: email,
      token: token_hash,
      expires_at: now + (24 * 3600),
      created_at: now,
      updated_at: now
    )

    jwt = Auth::Token.encode_invite(token: raw_token, email: email)
    { jwt: jwt, id: id }
  end
  # rubocop:enable Sorbet/BlockMethodDefinition

  it "accepts an invite for a new user" do
    invite = create_invite_with_token(email: "newuser@example.com")

    result = described_class.call(token_jwt: invite[:jwt])

    expect(result.success?).to be true
    expect(result.value![:message]).to include("Invitation accepted")

    # User was created
    user = User.find_by_email("newuser@example.com")
    expect(user).not_to be_nil

    # Membership was created
    membership = WorkspaceMembership.find_by_workspace_and_user(workspace[:id], user.id)
    expect(membership).not_to be_nil
    expect(membership.role).to eq("member")

    # Invite was marked as accepted
    invite_row = DB[:workspace_invites].where(id: invite[:id]).first
    expect(invite_row[:accepted_at]).not_to be_nil

    # Magic link email was sent
    expect(Mail::TestMailer.deliveries.length).to eq(1)
    email = Mail::TestMailer.deliveries.first
    expect(email.to).to include("newuser@example.com")
    expect(email.subject).to include("Sign in")
  end

  it "accepts an invite for an existing user" do
    existing = TestFactories.user(email: "existing@example.com")
    invite = create_invite_with_token(email: "existing@example.com")

    result = described_class.call(token_jwt: invite[:jwt])

    expect(result.success?).to be true

    # No new user created
    expect(DB[:users].where(email: "existing@example.com").count).to eq(1)

    # Membership was created
    membership = WorkspaceMembership.find_by_workspace_and_user(workspace[:id], existing[:id])
    expect(membership).not_to be_nil
  end

  it "handles case when user is already a member" do
    existing = TestFactories.user(email: "member@example.com")
    TestFactories.workspace_membership(workspace: workspace, user: existing)
    invite = create_invite_with_token(email: "member@example.com")

    result = described_class.call(token_jwt: invite[:jwt])

    expect(result.success?).to be true
    expect(result.value![:message]).to include("already a member")
  end

  it "returns failure for missing token" do
    result = described_class.call(token_jwt: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Token is required")
  end

  it "returns failure for invalid token" do
    result = described_class.call(token_jwt: "invalid-jwt")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid invitation link")
  end

  it "returns failure for expired invite" do
    raw_token = SecureRandom.hex(32)
    token_hash = Auth::Token.digest(raw_token)
    now = Time.now
    DB[:workspace_invites].insert(
      id: SecureRandom.uuid,
      workspace_id: workspace[:id],
      invited_by: inviter[:id],
      email: "expired@example.com",
      token: token_hash,
      expires_at: now - 1,
      created_at: now,
      updated_at: now
    )

    # Create a JWT that hasn't expired itself but the invite record has
    jwt = Auth::Token.encode_invite(token: raw_token, email: "expired@example.com")
    result = described_class.call(token_jwt: jwt)

    expect(result.failure?).to be true
    expect(result.failure.message).to include("no longer valid")
  end
end
