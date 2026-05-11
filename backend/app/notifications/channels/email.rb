# frozen_string_literal: true

module Notifications
  module Channels
    # Email channel: enqueues the kind's email delivery job and runs the
    # per-kind message build + SMTP send on the worker fiber.
    module Email
      class << self
        def deliver_later(kind_class:, data:)
          kind_class.email_delivery_job.perform_later(**data)
        end
      end
    end
  end
end
