# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mailers::WorkspaceInvite do
  before { Mail::TestMailer.deliveries.clear }

  let(:params) do
    {
      email: "invitee@example.com",
      invite_link: "https://tayaway.nl/invite?token=abc123",
      workspace_name: "My Team"
    }
  end

  describe ".send_email" do
    it "delivers one email to the invitee" do
      described_class.send_email(**params)

      expect(Mail::TestMailer.deliveries.length).to eq(1)
      expect(Mail::TestMailer.deliveries.first.to).to eq(["invitee@example.com"])
    end

    it "uses the workspace name in the subject" do
      described_class.send_email(**params)

      expect(Mail::TestMailer.deliveries.first.subject).to eq("Join My Team on Tayaway")
    end

    it "includes the invite link in both parts" do
      described_class.send_email(**params)
      message = Mail::TestMailer.deliveries.first

      expect(message.text_part.body.to_s).to include(params[:invite_link])
      expect(message.html_part.body.to_s).to include(params[:invite_link])
    end

    it "sets a display-name From" do
      described_class.send_email(**params)

      expect(Mail::TestMailer.deliveries.first[:from].formatted).to eq(["Tayaway <noreply@tayaway.com>"])
    end

    context "when an unsubscribe address is configured" do
      before { ENV["SMTP_UNSUBSCRIBE_EMAIL"] = "unsubscribe@tayaway.nl" }
      after { ENV.delete("SMTP_UNSUBSCRIBE_EMAIL") }

      it "sets a mailto List-Unsubscribe header" do
        described_class.send_email(**params)

        expect(Mail::TestMailer.deliveries.first["List-Unsubscribe"].to_s)
          .to eq("<mailto:unsubscribe@tayaway.nl?subject=unsubscribe>")
      end
    end

    context "without a configured unsubscribe address" do
      it "omits the List-Unsubscribe header" do
        described_class.send_email(**params)

        expect(Mail::TestMailer.deliveries.first["List-Unsubscribe"]).to be_nil
      end
    end

    context "with a recipient name" do
      it "greets by name in the text body" do
        described_class.send_email(**params.merge(name: "Alice"))

        expect(Mail::TestMailer.deliveries.first.text_part.body.to_s).to include("Hi Alice,")
      end
    end
  end
end
