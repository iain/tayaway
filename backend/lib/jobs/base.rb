# frozen_string_literal: true

module Jobs
  # Subclass to define a background job. Implement `call(**kwargs)` taking
  # the keyword arguments that should be persisted in the payload — each
  # invocation runs on a fresh instance, so there's no point holding state
  # in ivars and no need to override `initialize`.
  #
  # Argument contract: payloads are **flat scalar kwargs** — strings,
  # numbers, booleans, nil. Hashes and arrays of hashes are out of scope
  # because `.run` only symbolises top-level keys; a nested `{outer:
  # {inner: 1}}` would arrive as `{outer: {"inner" => 1}}` and confuse
  # any consumer reading nested keys with `.[:inner]`. If a future job
  # genuinely needs structured input, persist an ID and look the record
  # up in `call`.
  #
  # One job class per concrete delivery (e.g. one per mailer) rather
  # than a generic `DeliverEmail.new(mailer:, args:)` is intentional —
  # `job_class` is what shows up in queue rows, logs, and metrics, and
  # the per-mailer split keeps that signal legible.
  #
  # @example
  #   class Jobs::DeliverLoginLink < Jobs::Base
  #     def call(email:, login_link:, workspace_name: "Tayaway")
  #       Mailers::LoginLink.perform_delivery(
  #         email: email,
  #         login_link: login_link,
  #         workspace_name: workspace_name
  #       )
  #     end
  #   end
  #
  #   Jobs::DeliverLoginLink.perform_later(email: "x@y.z", login_link: "...")
  class Base
    class << self
      def perform_later(**args)
        Jobs::Queue.enqueue(job_class: name, args: args)
      end

      # Called by the worker to execute a persisted job. Ruby's `**hash`
      # splat requires symbol keys to bind to keyword parameters, but
      # JSONB round-trips keys as strings, so we symbolise on the way
      # in. The transform is shallow on purpose — see the flat-kwargs
      # contract above.
      def run(args)
        new.call(**args.transform_keys(&:to_sym))
      end
    end

    def call(**)
      raise NotImplementedError
    end
  end
end
