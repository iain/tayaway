# frozen_string_literal: true

require "spec_helper"

# Each mailer's `send_email` is meant to enqueue a Jobs::Deliver* job
# rather than build and send the message synchronously. The actual
# delivery side is covered transitively by service-layer specs (which
# inspect Mail::TestMailer.deliveries) and by perform_delivery in the
# individual mailer specs; this file just pins the enqueue contract so
# someone can't accidentally swap the call back to inline delivery.
RSpec.describe "mailer enqueue contracts" do
  before { allow(Jobs::Queue).to receive(:enqueue) }

  it "Mailers::LoginLink.send_email enqueues a DeliverLoginLink job" do
    Mailers::LoginLink.send_email(email: "u@example.com", login_link: "https://x", workspace_name: "WS")

    expect(Jobs::Queue).to have_received(:enqueue).with(
      job_class: "Jobs::DeliverLoginLink",
      args: { email: "u@example.com", login_link: "https://x", workspace_name: "WS" }
    )
  end

  it "Mailers::EmailChange.send_email enqueues a DeliverEmailChange job" do
    Mailers::EmailChange.send_email(email: "u@example.com", verification_link: "https://v")

    expect(Jobs::Queue).to have_received(:enqueue).with(
      job_class: "Jobs::DeliverEmailChange",
      args: { email: "u@example.com", verification_link: "https://v" }
    )
  end

  it "Mailers::WorkspaceInvite.send_email enqueues a DeliverWorkspaceInvite job" do
    Mailers::WorkspaceInvite.send_email(
      email: "u@example.com",
      invite_link: "https://i",
      workspace_name: "WS",
      name: "Iain"
    )

    expect(Jobs::Queue).to have_received(:enqueue).with(
      job_class: "Jobs::DeliverWorkspaceInvite",
      args: { email: "u@example.com", invite_link: "https://i", workspace_name: "WS", name: "Iain" }
    )
  end

  it "Mailers::PollClosed.send_email enqueues a DeliverPollClosed job" do
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
      job_class: "Jobs::DeliverPollClosed",
      args: hash_including(
        email: "u@example.com",
        event_name: "Trip",
        ics_filename: "trip.ics",
        auto_rsvped: false
      )
    )
  end
end
