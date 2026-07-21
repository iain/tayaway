# frozen_string_literal: true

require "spec_helper"

RSpec.describe AdminDb do
  describe ".connection" do
    it "falls back to the main DB connection when ADMIN_DATABASE_URL is unset" do
      expect(described_class.connection).to equal(DB)
    end

    context "with ADMIN_DATABASE_URL set" do
      after do
        described_class.instance_variable_get(:@connection)&.disconnect
        described_class.instance_variable_set(:@connection, nil)
      end

      it "mirrors the main connection's type extensions and timeouts" do
        APP_CONFIG.with(admin_database_url: APP_CONFIG.database_url) do
          conn = described_class.connection

          # The dashboard renders jsonb columns via #to_json; without pg_json
          # they come back as raw strings and double-encode.
          args = conn.get(Sequel.lit(%q('{"a": 1}'::jsonb)))
          expect(JSON.parse(args.to_json)).to eq("a" => 1)
          expect(conn.get(Sequel.function(:current_setting, "statement_timeout"))).to eq("30s")
        end
      end
    end
  end
end
