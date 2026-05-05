# frozen_string_literal: true

module Jobs
  class DeliverLoginLink < Base
    def initialize(email:, login_link:, workspace_name: "Tayaway")
      @email = email
      @login_link = login_link
      @workspace_name = workspace_name
    end

    def call
      Mailers::LoginLink.deliver_now(
        email: @email,
        login_link: @login_link,
        workspace_name: @workspace_name
      )
    end
  end
end
