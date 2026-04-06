# frozen_string_literal: true

require "spec_helper"

RSpec.describe PointParser do
  describe ".parse" do
    it "returns nil for nil input" do
      expect(described_class.parse(nil)).to be_nil
    end

    it "returns nil for an empty string" do
      expect(described_class.parse("")).to be_nil
    end

    it "returns nil for a malformed string without parentheses" do
      expect(described_class.parse("1.5,2.5")).to be_nil
    end

    it "returns nil for a string with only one value" do
      expect(described_class.parse("(1.5)")).to be_nil
    end

    it "returns nil for a non-string input" do
      expect(described_class.parse(42)).to be_nil
    end

    it "parses a valid POINT string into [longitude, latitude]" do
      expect(described_class.parse("(4.9041,52.3676)")).to eq([4.9041, 52.3676])
    end

    it "parses negative coordinates correctly" do
      expect(described_class.parse("(-73.9857,40.7484)")).to eq([-73.9857, 40.7484])
    end

    it "parses zero coordinates" do
      expect(described_class.parse("(0.0,0.0)")).to eq([0.0, 0.0])
    end
  end
end
