# frozen_string_literal: true

require "spec_helper"

# Each mailer's `send_email` is meant to enqueue its inner DeliveryJob
# rather than build and send the message synchronously. The actual
# delivery side is covered transitively by service-layer specs (which
# inspect Mail::TestMailer.deliveries) and by perform_delivery in the
# individual mailer specs; this file just pins the enqueue contract so
# someone can't accidentally swap the call back to inline delivery.
RSpec.describe "mailer enqueue contracts" do
  before { allow(Jobs::Queue).to receive(:enqueue) }

  it "Mailers::LoginLink.send_email enqueues a LoginLink::DeliveryJob" do
    Mailers::LoginLink.send_email(email: "u@example.com", login_link: "https://x", workspace_name: "WS")

    expect(Jobs::Queue).to have_received(:enqueue).with(
      job_class: "Mailers::LoginLink::DeliveryJob",
      args: { email: "u@example.com", login_link: "https://x", workspace_name: "WS" }
    )
  end

  it "Mailers::EmailChange.send_email enqueues an EmailChange::DeliveryJob" do
    Mailers::EmailChange.send_email(email: "u@example.com", verification_link: "https://v")

    expect(Jobs::Queue).to have_received(:enqueue).with(
      job_class: "Mailers::EmailChange::DeliveryJob",
      args: { email: "u@example.com", verification_link: "https://v" }
    )
  end

  it "Mailers::WorkspaceInvite.send_email enqueues a WorkspaceInvite::DeliveryJob" do
    Mailers::WorkspaceInvite.send_email(
      email: "u@example.com",
      invite_link: "https://i",
      workspace_name: "WS",
      name: "Iain"
    )

    expect(Jobs::Queue).to have_received(:enqueue).with(
      job_class: "Mailers::WorkspaceInvite::DeliveryJob",
      args: { email: "u@example.com", invite_link: "https://i", workspace_name: "WS", name: "Iain" }
    )
  end

  it "Mailers::PollClosed.send_email enqueues a PollClosed::DeliveryJob" do
    Mailers::PollClosed.send_email(
      email: "u@example.com",
      user_name: "Iain",
      event_name: "Trip",
      date_label: "Aug 1",
      event_url: "https://e",
      ics_content: "BEGIN:VCALENDAR\nEND:VCALENDAR\n",
      ics_filename: "trip.ics",
      auto_rsvped: false
    )

    expect(Jobs::Queue).to have_received(:enqueue).with(
      job_class: "Mailers::PollClosed::DeliveryJob",
      args: hash_including(
        email: "u@example.com",
        event_name: "Trip",
        ics_filename: "trip.ics",
        auto_rsvped: false
      )
    )
  end
end
