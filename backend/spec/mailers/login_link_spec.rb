# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mailers::LoginLink do
  before { Mail::TestMailer.deliveries.clear }

  describe ".send_email" do
    let(:email) { "user@example.com" }
    let(:login_link) { "https://tayaway.nl/auth/verify?token=abc123" }

    context "with default workspace name" do
      before { described_class.send_email(email: email, login_link: login_link) }

      it "delivers one email" do
        expect(Mail::TestMailer.deliveries.length).to eq(1)
      end

      it "sends to the correct recipient" do
        expect(Mail::TestMailer.deliveries.first.to).to eq([email])
      end

      it "sends from the configured address" do
        expect(Mail::TestMailer.deliveries.first.from).to eq(["noreply@tayaway.nl"])
      end

      it "has the default subject" do
        expect(Mail::TestMailer.deliveries.first.subject).to eq("Log in to Tayaway")
      end

      it "includes the login link in the text part" do
        message = Mail::TestMailer.deliveries.first
        text_body = message.text_part.body.to_s

        expect(text_body).to include(login_link)
      end

      it "includes the login link in the HTML part" do
        message = Mail::TestMailer.deliveries.first
        html_body = message.html_part.body.to_s

        expect(html_body).to include(login_link)
      end

      it "has both text and HTML parts" do
        message = Mail::TestMailer.deliveries.first

        expect(message.text_part).not_to be_nil
        expect(message.html_part).not_to be_nil
      end

      it "sets a display-name From" do
        expect(Mail::TestMailer.deliveries.first[:from].formatted).to eq(["Tayaway <noreply@tayaway.nl>"])
      end

      it "does not set a List-Unsubscribe header" do
        expect(Mail::TestMailer.deliveries.first["List-Unsubscribe"]).to be_nil
      end
    end

    context "when an unsubscribe address is configured" do
      it "still does not set a List-Unsubscribe header (login is user-requested)" do
        APP_CONFIG.with(smtp_unsubscribe_email: "unsubscribe@tayaway.nl") do
          described_class.send_email(email: email, login_link: login_link)
          expect(Mail::TestMailer.deliveries.first["List-Unsubscribe"]).to be_nil
        end
      end
    end

    context "with custom workspace name" do
      before { described_class.send_email(email: email, login_link: login_link, workspace_name: "My Team") }

      it "uses the workspace name in the subject" do
        expect(Mail::TestMailer.deliveries.first.subject).to eq("Log in to My Team")
      end

      it "uses the workspace name in the text body" do
        text_body = Mail::TestMailer.deliveries.first.text_part.body.to_s

        expect(text_body).to include("Log in to My Team")
      end

      it "uses the workspace name in the HTML body" do
        html_body = Mail::TestMailer.deliveries.first.html_part.body.to_s

        expect(html_body).to include("Log in to My Team")
      end
    end
  end
end
