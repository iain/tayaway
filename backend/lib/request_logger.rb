# typed: true
# frozen_string_literal: true

# Rack middleware that logs HTTP requests in a clean, readable format.
#
#   POST /api/auth/verify 200 4.2ms
#
class RequestLogger
  extend T::Sig

  sig { params(app: T.untyped).void }
  def initialize(app)
    @app = app
  end

  sig { params(env: T::Hash[String, T.untyped]).returns(T.untyped) }
  def call(env)
    began_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, headers, body = @app.call(env)
    log(env, status, began_at)
    [status, headers, body]
  rescue StandardError => e
    log(env, 500, T.must(began_at))
    APP_LOGGER.error { "#{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}" }
    raise
  end

  private

  sig { params(env: T::Hash[String, T.untyped], status: Integer, began_at: T.any(Float, Integer)).void }
  def log(env, status, began_at)
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - began_at
    method = env["REQUEST_METHOD"]
    path = env["PATH_INFO"]
    query = env["QUERY_STRING"]
    path = "#{path}?#{query}" unless query.nil? || query.empty?

    APP_LOGGER.info { "#{method} #{path} #{status} #{format_duration(duration)}" }
  end

  sig { params(seconds: T.any(Float, Integer)).returns(String) }
  def format_duration(seconds)
    if seconds < 1
      "#{(seconds * 1000).round(1)}ms"
    else
      "#{seconds.round(2)}s"
    end
  end
end
