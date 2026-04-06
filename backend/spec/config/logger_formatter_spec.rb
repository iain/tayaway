# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Logger JSON formatter" do
  let(:production_formatter) do
    proc { |severity, time, _progname, msg|
      JSON.generate({ timestamp: time.utc.iso8601(3), level: severity, message: msg.to_s }) + "\n"
    }
  end

  let(:time) { Time.utc(2026, 3, 25, 12, 0, 0) }

  it "emits valid JSON terminated by a newline" do
    output = production_formatter.call("INFO", time, nil, "hello world")

    expect(output).to end_with("\n")
    expect { JSON.parse(output) }.not_to raise_error
  end

  it "includes the message field" do
    output = production_formatter.call("INFO", time, nil, "login attempted")
    parsed = JSON.parse(output)

    expect(parsed["message"]).to eq("login attempted")
  end

  it "includes the level field" do
    output = production_formatter.call("WARN", time, nil, "something odd")
    parsed = JSON.parse(output)

    expect(parsed["level"]).to eq("WARN")
  end

  it "includes an ISO 8601 timestamp with milliseconds" do
    output = production_formatter.call("INFO", time, nil, "event")
    parsed = JSON.parse(output)

    expect(parsed["timestamp"]).to eq("2026-03-25T12:00:00.000Z")
  end

  it "produces one JSON object per line" do
    output = production_formatter.call("ERROR", time, nil, "bad thing happened")

    lines = output.lines
    expect(lines.length).to eq(1)
    expect { JSON.parse(lines.first) }.not_to raise_error
  end

  it "serializes an Exception message via .to_s" do
    error = StandardError.new("something broke")
    output = production_formatter.call("ERROR", time, nil, error)
    parsed = JSON.parse(output)

    expect(parsed["message"]).to eq("something broke")
  end
end
