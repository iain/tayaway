# frozen_string_literal: true

require "spec_helper"

RSpec.describe Encryption do
  describe ".encrypt / .decrypt" do
    it "round-trips a plaintext IBAN" do
      iban = "NL91ABNA0417164300"
      encrypted = described_class.encrypt(iban)
      expect(described_class.decrypt(encrypted)).to eq(iban)
    end

    it "produces different ciphertext on each call (random nonce)" do
      iban = "DE89370400440532013000"
      first = described_class.encrypt(iban)
      second = described_class.encrypt(iban)
      expect(first).not_to eq(second)
    end

    it "produces Base64-encoded output" do
      encrypted = described_class.encrypt("GB29NWBK60161331926819")
      expect { Base64.strict_decode64(encrypted) }.not_to raise_error
    end
  end

  describe ".encrypted?" do
    it "returns false for a plaintext IBAN" do
      expect(described_class.encrypted?("NL91ABNA0417164300")).to be(false)
    end

    it "returns true for an encrypted value" do
      encrypted = described_class.encrypt("NL91ABNA0417164300")
      expect(described_class.encrypted?(encrypted)).to be(true)
    end

    it "returns false for a short Base64 string (not enough bytes)" do
      # Base64 of just a few bytes — too short to be valid ciphertext
      short = Base64.strict_encode64("tooshort")
      expect(described_class.encrypted?(short)).to be(false)
    end

    it "returns false for a non-Base64 string" do
      expect(described_class.encrypted?("not base64!!!")).to be(false)
    end
  end
end
