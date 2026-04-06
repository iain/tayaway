# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mailers::PollClosed do
  before { Mail::TestMailer.deliveries.clear }

  let(:base_params) do
    {
      email: "voter@example.com",
      user_name: "Alice",
      event_name: "Summer Trip",
      date_label: "March 10-12, 2026",
      event_url: "https://tayaway.com/events/abc123",
      ics_content: "BEGIN:VCALENDAR\r\nEND:VCALENDAR",
      ics_filename: "summer-trip.ics",
      auto_rsvped: false
    }
  end

  describe ".send_email" do
    it "delivers one email" do
      described_class.send_email(**base_params)

      expect(Mail::TestMailer.deliveries.length).to eq(1)
    end

    it "sends to the correct recipient" do
      described_class.send_email(**base_params)

      expect(Mail::TestMailer.deliveries.first.to).to eq(["voter@example.com"])
    end

    it "has the correct subject" do
      described_class.send_email(**base_params)

      expect(Mail::TestMailer.deliveries.first.subject).to eq("Dates confirmed for Summer Trip")
    end

    it "includes the date label in the text body" do
      described_class.send_email(**base_params)
      text_body = Mail::TestMailer.deliveries.first.text_part.body.to_s

      expect(text_body).to include("March 10-12, 2026")
    end

    it "includes the date label in the HTML body" do
      described_class.send_email(**base_params)
      html_body = Mail::TestMailer.deliveries.first.html_part.body.to_s

      expect(html_body).to include("March 10-12, 2026")
    end

    it "includes the event URL in the text body" do
      described_class.send_email(**base_params)
      text_body = Mail::TestMailer.deliveries.first.text_part.body.to_s

      expect(text_body).to include("https://tayaway.com/events/abc123")
    end

    it "includes the event URL as a link in the HTML body" do
      described_class.send_email(**base_params)
      html_body = Mail::TestMailer.deliveries.first.html_part.body.to_s

      expect(html_body).to include('href="https://tayaway.com/events/abc123"')
    end

    it "attaches the ICS file" do
      described_class.send_email(**base_params)
      message = Mail::TestMailer.deliveries.first

      expect(message.attachments.length).to eq(1)
      expect(message.attachments.first.filename).to eq("summer-trip.ics")
    end

    it "has both text and HTML parts" do
      described_class.send_email(**base_params)
      message = Mail::TestMailer.deliveries.first

      expect(message.text_part).not_to be_nil
      expect(message.html_part).not_to be_nil
    end

    context "with user name" do
      it "greets the user by name" do
        described_class.send_email(**base_params.merge(user_name: "Alice"))
        text_body = Mail::TestMailer.deliveries.first.text_part.body.to_s

        expect(text_body).to include("Hi Alice,")
      end
    end

    context "without user name" do
      it "uses a generic greeting" do
        described_class.send_email(**base_params.merge(user_name: nil))
        text_body = Mail::TestMailer.deliveries.first.text_part.body.to_s

        expect(text_body).to include("Hi,")
        expect(text_body).not_to include("Hi ,")
      end
    end

    context "when auto-RSVPed" do
      it "shows the auto-RSVP message" do
        described_class.send_email(**base_params.merge(auto_rsvped: true))
        text_body = Mail::TestMailer.deliveries.first.text_part.body.to_s

        expect(text_body).to include("You've been RSVPed as attending based on your vote.")
      end
    end

    context "when not auto-RSVPed" do
      it "shows the RSVP prompt message" do
        described_class.send_email(**base_params.merge(auto_rsvped: false))
        text_body = Mail::TestMailer.deliveries.first.text_part.body.to_s

        expect(text_body).to include("Head to the event page to RSVP")
      end
    end
  end
end
