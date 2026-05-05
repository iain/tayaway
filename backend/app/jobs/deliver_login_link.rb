# frozen_string_literal: true

module Jobs
  class DeliverLoginLink < Base
    def call(email:, login_link:, workspace_name: "Tayaway")
      Mailers::LoginLink.perform_delivery(
        email: email,
        login_link: login_link,
        workspace_name: workspace_name
      )
    end
  end
end
