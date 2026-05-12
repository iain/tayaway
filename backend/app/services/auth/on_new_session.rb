# frozen_string_literal: true

module Auth
  # Sent only when this (browser, country) combination is novel for the
  # user in the last 30 days. The first session a user ever has trips
  # it (welcome and confirmation that login worked); a repeat sign-in
  # from the same browser and country stays quiet — the novelty check
  # owns the "is this worth telling them?" decision so the caller just
  # hands over the freshly-created session details.
  module OnNewSession
    class << self
      def call(user_id:, session_id:, browser_info:, geo:)
        Notifications::Safely.deliver(context: "Auth::OnNewSession") do
          browser_name = browser_info&.dig(:browser_name)
          country = geo&.dig(:country)
          return if seen_before?(user_id, session_id, browser_name, country)

          user = User.find(user_id)
          return unless user

          Notifications::Dispatch.call(
            kind: :new_session,
            user_id: user_id.to_s,
            data: {
              email: user.email.to_s,
              recipient_name: user.name,
              browser_name: browser_name,
              os_name: browser_info&.dig(:os_name),
              city: geo&.dig(:city),
              country: country,
              session_url: "#{FRONTEND_URL}/settings/login"
            }
          )
        end
      end

      private

      def seen_before?(user_id, session_id, browser_name, country)
        DB[:sessions]
          .where(user_id: user_id)
          .exclude(id: session_id)
          .where(browser_name: browser_name, country: country)
          .where { created_at >= (Time.now - (30 * 86_400)) }
          .any?
      end
    end
  end
end
