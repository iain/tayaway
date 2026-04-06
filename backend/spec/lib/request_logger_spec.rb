# frozen_string_literal: true

require "spec_helper"

RSpec.describe RequestLogger do
  let(:inner_app) { ->(_env) { [200, {}, ["OK"]] } }
  let(:middleware) { described_class.new(inner_app) }
  let(:env) { { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/api/health", "QUERY_STRING" => "" } }
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output) }

  before do
    stub_const("APP_LOGGER", logger)
  end

  describe "#call" do
    it "returns the upstream response unchanged" do
      status, _headers, body = middleware.call(env)

      expect(status).to eq(200)
      expect(body).to eq(["OK"])
    end

    it "logs the request method, path, status, and duration" do
      middleware.call(env)

      expect(log_output.string).to include("GET /api/health 200")
    end

    it "includes the query parameter name but redacts the value" do
      env["QUERY_STRING"] = "foo=bar"
      middleware.call(env)

      expect(log_output.string).to include("GET /api/health?foo=[REDACTED] 200")
      expect(log_output.string).not_to include("bar")
    end

    it "redacts the WebSocket ticket JWT from the logged path" do
      env["PATH_INFO"] = "/ws"
      env["QUERY_STRING"] = "ticket=eyJhbGciOiJIUzI1NiJ9.secret"
      middleware.call(env)

      expect(log_output.string).to include("GET /ws?ticket=[REDACTED] 200")
      expect(log_output.string).not_to include("eyJhbGciOiJIUzI1NiJ9")
    end

    it "redacts all values when multiple query parameters are present" do
      env["QUERY_STRING"] = "token=abc123&other=xyz"
      middleware.call(env)

      expect(log_output.string).to include("GET /api/health?token=[REDACTED]&other=[REDACTED] 200")
      expect(log_output.string).not_to include("abc123")
      expect(log_output.string).not_to include("xyz")
    end

    it "omits the query string separator when query string is empty" do
      middleware.call(env)

      expect(log_output.string).not_to include("?")
    end

    context "when the upstream app raises an exception" do
      let(:error) { RuntimeError.new("something went wrong") }
      let(:inner_app) { ->(_env) { raise error } }

      it "re-raises the exception" do
        expect { middleware.call(env) }.to raise_error(RuntimeError, "something went wrong")
      end

      it "logs the request line with status 500" do
        middleware.call(env) rescue nil

        expect(log_output.string).to include("GET /api/health 500")
      end

      it "logs the exception class and message" do
        middleware.call(env) rescue nil

        expect(log_output.string).to include("RuntimeError")
        expect(log_output.string).to include("something went wrong")
      end

      it "logs the backtrace" do
        middleware.call(env) rescue nil

        expect(log_output.string).to include("request_logger_spec.rb")
      end
    end
  end
end
