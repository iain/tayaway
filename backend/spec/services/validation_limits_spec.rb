# frozen_string_literal: true

require "spec_helper"

RSpec.describe ValidationLimits do
  describe ".parse_coordinate" do
    it "parses a valid float string" do
      expect(described_class.parse_coordinate("52.52")).to eq(52.52)
    end

    it "parses a negative float string" do
      expect(described_class.parse_coordinate("-13.405")).to eq(-13.405)
    end

    it "passes through a numeric value" do
      expect(described_class.parse_coordinate(52.52)).to eq(52.52)
    end

    it "passes through an integer value" do
      expect(described_class.parse_coordinate(10)).to eq(10.0)
    end

    it "returns nil for nil" do
      expect(described_class.parse_coordinate(nil)).to be_nil
    end

    it "returns nil for empty string" do
      expect(described_class.parse_coordinate("")).to be_nil
    end

    it "returns nil for blank string" do
      expect(described_class.parse_coordinate("   ")).to be_nil
    end

    it "returns nil for non-numeric string" do
      expect(described_class.parse_coordinate("abc")).to be_nil
    end

    it "returns nil for mixed string" do
      expect(described_class.parse_coordinate("52.52abc")).to be_nil
    end
  end
end
