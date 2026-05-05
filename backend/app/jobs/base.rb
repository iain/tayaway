# frozen_string_literal: true

module Jobs
  # Subclass to define a background job. Implement `call` and any keyword
  # arguments that should be persisted in the job's payload. Keyword
  # arguments are JSON-serialised on enqueue and reconstructed on the
  # other side.
  #
  # @example
  #   class Jobs::Mail::DeliverLoginLink < Jobs::Base
  #     def initialize(email:, login_link:, workspace_name: "Tayaway")
  #       @email = email
  #       @login_link = login_link
  #       @workspace_name = workspace_name
  #     end
  #
  #     def call
  #       Mailers::LoginLink.deliver_now(
  #         email: @email,
  #         login_link: @login_link,
  #         workspace_name: @workspace_name
  #       )
  #     end
  #   end
  #
  #   Jobs::Mail::DeliverLoginLink.perform_later(email: "x@y.z", login_link: "...")
  class Base
    class << self
      def perform_later(**args)
        Jobs::Queue.enqueue(job_class: name, args: args)
      end

      # Called by the worker to execute a persisted job. Symbolises keys
      # because JSONB round-trips keys as strings and our initializers
      # take keyword arguments.
      def run(args)
        new(**args.transform_keys(&:to_sym)).call
      end
    end

    def call
      raise NotImplementedError
    end
  end
end
