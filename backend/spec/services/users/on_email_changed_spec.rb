# frozen_string_literal: true

require "spec_helper"

RSpec.describe Users::OnEmailChanged do
  describe ".call" do
    let(:user) { TestFactories.user(name: "Iain") }

    it "sends the alert email to the OLD address" do
      Mail::TestMailer.deliveries.clear

      described_class.call(
        user_id: user[:id],
        old_email: "old@example.com",
        new_email: "new@example.com"
      )

      message = Mail::TestMailer.deliveries.first
      expect(message.to).to eq(["old@example.com"])
      expect(message.text_part.body.to_s).to include("new@example.com")
    end

    it "writes an in-app notification keyed to the affected user" do
      described_class.call(
        user_id: user[:id],
        old_email: "old@example.com",
        new_email: "new@example.com"
      )

      row = DB[:notifications].where(user_id: user[:id], kind: "email_change_completed").first
      expect(row).not_to be_nil
      expect(row[:data]["body"]).to include("old@example.com").and include("new@example.com")
    end
  end
end
