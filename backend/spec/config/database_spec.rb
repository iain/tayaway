# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Database configuration" do
  it "enforces a pool timeout so callers never wait indefinitely for a connection" do
    expect(DB.opts[:pool_timeout]).to eq(5)
  end

  it "enforces a connect timeout so unresponsive PostgreSQL does not hang" do
    expect(DB.opts[:connect_timeout]).to eq(5)
  end

  it "enforces a statement timeout on every connection" do
    result = DB.fetch("SHOW statement_timeout").first
    expect(result[:statement_timeout]).to eq("30s")
  end
end
