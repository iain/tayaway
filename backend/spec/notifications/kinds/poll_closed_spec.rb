# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Kinds::PollClosed do
  let(:base_params) do
    {
      email: "voter@example.com",
      user_name: "Alice",
      event_name: "Summer Trip",
      date_label: "March 10-12, 2026",
      event_url: "https://tayaway.nl/events/abc123",
      ics_content: "BEGIN:VCALENDAR\r\nEND:VCALENDAR",
      ics_filename: "summer-trip.ics",
      auto_rsvped: false
    }
  end

  describe ".build_email" do
    it "sends to the correct recipient" do
      message = described_class.build_email(**base_params)

      expect(message.to).to eq(["voter@example.com"])
    end

    it "has the correct subject" do
      message = described_class.build_email(**base_params)

      expect(message.subject).to eq("Dates confirmed for Summer Trip")
    end

    it "includes the date label in the text body" do
      message = described_class.build_email(**base_params)

      expect(message.text_part.body.to_s).to include("March 10-12, 2026")
    end

    it "includes the date label in the HTML body" do
      message = described_class.build_email(**base_params)

      expect(message.html_part.body.to_s).to include("March 10-12, 2026")
    end

    it "includes the event URL in the text body" do
      message = described_class.build_email(**base_params)

      expect(message.text_part.body.to_s).to include("https://tayaway.nl/events/abc123")
    end

    it "includes the event URL as a link in the HTML body" do
      message = described_class.build_email(**base_params)

      expect(message.html_part.body.to_s).to include('href="https://tayaway.nl/events/abc123"')
    end

    it "attaches the ICS file" do
      message = described_class.build_email(**base_params)

      expect(message.attachments.length).to eq(1)
      expect(message.attachments.first.filename).to eq("summer-trip.ics")
    end

    it "has both text and HTML parts" do
      message = described_class.build_email(**base_params)

      expect(message.text_part).not_to be_nil
      expect(message.html_part).not_to be_nil
    end

    context "with user name" do
      it "greets the user by name" do
        message = described_class.build_email(**base_params.merge(user_name: "Alice"))

        expect(message.text_part.body.to_s).to include("Hi Alice,")
      end
    end

    context "without user name" do
      it "uses a generic greeting" do
        message = described_class.build_email(**base_params.merge(user_name: nil))
        text_body = message.text_part.body.to_s

        expect(text_body).to include("Hi,")
        expect(text_body).not_to include("Hi ,")
      end
    end

    context "when auto-RSVPed" do
      it "shows the auto-RSVP message" do
        message = described_class.build_email(**base_params.merge(auto_rsvped: true))

        expect(message.text_part.body.to_s).to include("You've been RSVPed as attending based on your vote.")
      end
    end

    context "when not auto-RSVPed" do
      it "shows the RSVP prompt message" do
        message = described_class.build_email(**base_params.merge(auto_rsvped: false))

        expect(message.text_part.body.to_s).to include("Head to the event page to RSVP")
      end
    end

    it "sets a display-name From" do
      message = described_class.build_email(**base_params)

      expect(message[:from].formatted).to eq(["Tayaway <noreply@tayaway.nl>"])
    end

    it "does not set List-Unsubscribe when no unsubscribe address is configured" do
      message = described_class.build_email(**base_params)

      expect(message["List-Unsubscribe"]).to be_nil
    end

    context "when an unsubscribe address is configured" do
      before { ENV["SMTP_UNSUBSCRIBE_EMAIL"] = "unsubscribe@tayaway.nl" }
      after { ENV.delete("SMTP_UNSUBSCRIBE_EMAIL") }

      it "sets a mailto List-Unsubscribe header" do
        message = described_class.build_email(**base_params)

        expect(message["List-Unsubscribe"].to_s)
          .to eq("<mailto:unsubscribe@tayaway.nl?subject=unsubscribe>")
      end
    end
  end
end
