# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe RequestLogger do
  let(:inner_app) { ->(env) { [200, {}, ["OK"]] } }
  let(:middleware) { described_class.new(inner_app) }
  let(:env) { { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/api/health", "QUERY_STRING" => "" } }
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output) }

  before do
    stub_const("APP_LOGGER", logger)
  end

  describe "#call" do
    it "returns the upstream response unchanged" do
      status, headers, body = middleware.call(env)

      expect(status).to eq(200)
      expect(body).to eq(["OK"])
    end

    it "logs the request method, path, status, and duration" do
      middleware.call(env)

      expect(log_output.string).to include("GET /api/health 200")
    end

    it "includes the query string in the log when present" do
      env["QUERY_STRING"] = "foo=bar"
      middleware.call(env)

      expect(log_output.string).to include("GET /api/health?foo=bar 200")
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
