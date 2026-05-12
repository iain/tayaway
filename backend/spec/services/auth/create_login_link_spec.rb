# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::CreateLoginLink do
  before { allow(Mailers::LoginLink).to receive(:send_email) }

  it "returns failure when email is missing" do
    result = described_class.call(email: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Email is required")
  end

  it "returns success and creates login link token for existing user" do
    user = TestFactories.user(email: "test@example.com")

    result = described_class.call(email: "test@example.com")

    expect(result.success?).to be true
    expect(result.value![:message]).to include("If an account exists")
    expect(DB[:login_link_tokens].where(user_id: user[:id]).count).to eq(1)
  end

  it "generates a URL with a single JWT token parameter" do
    TestFactories.user(email: "test@example.com")
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    APP_CONFIG.with(app_env: "development") do
      described_class.call(email: "test@example.com")
    end

    login_link_log = logged_messages.find { |m| m.include?("LOGIN LINK") }
    expect(login_link_log).to match(/auth\/verify\?token=eyJ/)
  end

  it "returns success without creating token for non-existent user" do
    result = described_class.call(email: "nonexistent@example.com")

    expect(result.success?).to be true
    expect(result.value![:message]).to include("If an account exists")
    expect(DB[:login_link_tokens].count).to eq(0)
  end

  it "sends a login link email for existing user" do
    TestFactories.user(email: "test@example.com")

    described_class.call(email: "test@example.com")

    expect(Mailers::LoginLink).to have_received(:send_email).with(
      email: "test@example.com",
      login_link: a_string_matching(%r{auth/verify\?token=eyJ}),
      workspace_name: "Tayaway"
    )
  end

  it "passes workspace name when user belongs to exactly one workspace" do
    user_row = TestFactories.user(email: "test@example.com")
    workspace = TestFactories.workspace(name: "My Team")
    TestFactories.workspace_membership(workspace: workspace, user: user_row)

    described_class.call(email: "test@example.com")

    expect(Mailers::LoginLink).to have_received(:send_email).with(
      email: "test@example.com",
      login_link: a_string_matching(%r{auth/verify\?token=eyJ}),
      workspace_name: "My Team"
    )
  end

  it "falls back to Tayaway when user belongs to multiple workspaces" do
    user_row = TestFactories.user(email: "test@example.com")
    workspace1 = TestFactories.workspace(name: "Team A")
    workspace2 = TestFactories.workspace(name: "Team B")
    TestFactories.workspace_membership(workspace: workspace1, user: user_row)
    TestFactories.workspace_membership(workspace: workspace2, user: user_row)

    described_class.call(email: "test@example.com")

    expect(Mailers::LoginLink).to have_received(:send_email).with(
      email: "test@example.com",
      login_link: a_string_matching(%r{auth/verify\?token=eyJ}),
      workspace_name: "Tayaway"
    )
  end

  it "does not send email for non-existent user" do
    described_class.call(email: "nonexistent@example.com")

    expect(Mailers::LoginLink).not_to have_received(:send_email)
  end
end
