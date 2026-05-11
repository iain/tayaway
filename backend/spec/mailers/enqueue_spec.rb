# frozen_string_literal: true

require "spec_helper"

# Pin the auth-flow mailers' enqueue contract: a request-path call to
# `send_email` must enqueue the inner DeliveryJob rather than build and
# send the message synchronously, so the SMTP round-trip stays off the
# request fiber. The actual delivery side is covered transitively by
# service-layer specs and per-mailer specs; this file just guards the
# enqueue side from accidentally being swapped back to inline delivery.
# Notification-system kinds (workspace invite, poll closed) live under
# `Notifications::Dispatch` and their enqueue contract is in
# `spec/services/notifications/dispatch_spec.rb`.
RSpec.describe "auth-mailer enqueue contracts" do
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
end
