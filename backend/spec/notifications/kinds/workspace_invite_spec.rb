# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Kinds::WorkspaceInvite do
  let(:params) do
    {
      email: "invitee@example.com",
      invite_link: "https://tayaway.nl/invite?token=abc123",
      workspace_name: "My Team"
    }
  end

  describe ".build_email" do
    it "addresses the invitee" do
      message = described_class.build_email(**params)

      expect(message.to).to eq(["invitee@example.com"])
    end

    it "uses the workspace name in the subject" do
      message = described_class.build_email(**params)

      expect(message.subject).to eq("Join My Team on Tayaway")
    end

    it "includes the invite link in both parts" do
      message = described_class.build_email(**params)

      expect(message.text_part.body.to_s).to include(params[:invite_link])
      expect(message.html_part.body.to_s).to include(params[:invite_link])
    end

    it "sets a display-name From" do
      message = described_class.build_email(**params)

      expect(message[:from].formatted).to eq(["Tayaway <noreply@tayaway.nl>"])
    end

    context "when an unsubscribe address is configured" do
      before { ENV["SMTP_UNSUBSCRIBE_EMAIL"] = "unsubscribe@tayaway.nl" }
      after { ENV.delete("SMTP_UNSUBSCRIBE_EMAIL") }

      it "sets a mailto List-Unsubscribe header" do
        message = described_class.build_email(**params)

        expect(message["List-Unsubscribe"].to_s)
          .to eq("<mailto:unsubscribe@tayaway.nl?subject=unsubscribe>")
      end
    end

    context "without a configured unsubscribe address" do
      it "omits the List-Unsubscribe header" do
        message = described_class.build_email(**params)

        expect(message["List-Unsubscribe"]).to be_nil
      end
    end

    context "with a recipient name" do
      it "greets by name in the text body" do
        message = described_class.build_email(**params.merge(name: "Alice"))

        expect(message.text_part.body.to_s).to include("Hi Alice,")
      end
    end
  end
end
