# frozen_string_literal: true

module Jobs
  class DeliverEmailChange < Base
    def initialize(email:, verification_link:)
      super()
      @email = email
      @verification_link = verification_link
    end

    def call
      Mailers::EmailChange.deliver_now(email: @email, verification_link: @verification_link)
    end
  end
end
