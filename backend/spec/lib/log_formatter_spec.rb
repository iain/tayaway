# frozen_string_literal: true

require "spec_helper"

RSpec.describe LogFormatter do
  after { RequestContext.reset! }

  describe ".production" do
    let(:formatter) { described_class.production }
    let(:time) { Time.utc(2026, 4, 26, 12, 0, 0) }

    it "emits a JSON line without request_id when none is set" do
      line = formatter.call("INFO", time, nil, "hello")
      payload = JSON.parse(line)
      expect(payload).to eq("timestamp" => "2026-04-26T12:00:00.000Z", "level" => "INFO", "message" => "hello")
    end

    it "includes request_id when RequestContext carries one" do
      RequestContext.with(request_id: "req-abc") do
        line = formatter.call("WARN", time, nil, "thing happened")
        expect(JSON.parse(line)).to include("request_id" => "req-abc")
      end
    end
  end

  describe ".human_readable" do
    let(:formatter) { described_class.human_readable }

    it "tags the line with a [req=…] prefix when a request_id is set" do
      RequestContext.with(request_id: "req-abc") do
        expect(formatter.call("INFO", Time.now, nil, "hello")).to eq("[INFO] [req=req-abc] hello\n")
      end
    end

    it "omits the tag when no request_id is set" do
      expect(formatter.call("INFO", Time.now, nil, "hello")).to eq("[INFO] hello\n")
    end

    it "drops the level label for DEBUG" do
      expect(formatter.call("DEBUG", Time.now, nil, "noisy")).to eq("noisy\n")
    end
  end
end
