# typed: true
# frozen_string_literal: true

# Application-wide configuration

module Tayaway
  class << self
    def env
      ENV.fetch("RACK_ENV", "development")
    end

    def development?
      env == "development"
    end

    def test?
      env == "test"
    end

    def production?
      env == "production"
    end
  end
end
