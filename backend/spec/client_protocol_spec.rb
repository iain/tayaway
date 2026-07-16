# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClientProtocol do
  describe ".supported?" do
    before { stub_const("ClientProtocol::MIN_SUPPORTED_VERSION", 3) }

    it "accepts a version at exactly the minimum" do
      expect(described_class.supported?("3")).to be true
    end

    it "accepts a newer version" do
      expect(described_class.supported?("4")).to be true
    end

    it "rejects an older version" do
      expect(described_class.supported?("2")).to be false
    end

    it "treats a missing version as 0" do
      expect(described_class.supported?(nil)).to be false
    end

    it "treats a non-numeric version as 0" do
      expect(described_class.supported?("banana")).to be false
    end

    it "treats a malformed repeated query param as 0" do
      expect(described_class.supported?(%w[3 4])).to be false
    end
  end

  describe "MIN_SUPPORTED_VERSION" do
    it "is 0 so pre-versioning clients (no header) remain supported" do
      expect(ClientProtocol::MIN_SUPPORTED_VERSION).to eq(0)
      expect(described_class.supported?(nil)).to be true
    end
  end
end
