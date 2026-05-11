# frozen_string_literal: true

require "spec_helper"

RSpec.describe Invites::OnSent do
  describe ".call" do
    let(:workspace) { TestFactories.workspace }

    it "sends an invite email to the invitee" do
      Mail::TestMailer.deliveries.clear

      described_class.call(
        email: "invitee@example.com",
        invite_link: "https://example.test/invite/abc",
        workspace_id: workspace[:id]
      )

      message = Mail::TestMailer.deliveries.first
      expect(message).not_to be_nil
      expect(message.to).to eq(["invitee@example.com"])
      expect(message.text_part.body.to_s).to include("https://example.test/invite/abc")
    end

    it "writes a notification row when the invitee already has a user" do
      existing = TestFactories.user(email: "known@example.com")

      described_class.call(
        email: "known@example.com",
        invite_link: "https://example.test/invite/xyz",
        workspace_id: workspace[:id]
      )

      expect(DB[:notifications].where(user_id: existing[:id], kind: "workspace_invite").count).to eq(1)
    end

    it "still mails when the invitee has no user yet" do
      Mail::TestMailer.deliveries.clear

      described_class.call(
        email: "stranger@example.com",
        invite_link: "https://example.test/invite/xyz",
        workspace_id: workspace[:id]
      )

      expect(Mail::TestMailer.deliveries.length).to eq(1)
      expect(DB[:notifications].count).to eq(0)
    end
  end
end
