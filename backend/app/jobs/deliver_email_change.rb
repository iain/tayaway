# frozen_string_literal: true

module Jobs
  class DeliverEmailChange < Base
    def call(email:, verification_link:)
      Mailers::EmailChange.perform_delivery(email: email, verification_link: verification_link)
    end
  end
end
