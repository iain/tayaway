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

    it "produces Base64-encoded output with v1 prefix" do
      encrypted = described_class.encrypt("GB29NWBK60161331926819")
      raw = Base64.strict_decode64(encrypted)
      expect(raw.getbyte(0)).to eq(0x01)
    end

    it "decrypts legacy unversioned ciphertext" do
      # Simulate the old format: Base64(nonce ‖ mac ‖ ct) without version byte
      box = RbNaCl::SimpleBox.from_secret_key(described_class.send(:encryption_key))
      legacy = Base64.strict_encode64(box.box("NL91ABNA0417164300"))
      expect(described_class.decrypt(legacy)).to eq("NL91ABNA0417164300")
    end
  end

  describe ".encrypted?" do
    it "returns false for a plaintext IBAN" do
      expect(described_class.encrypted?("NL91ABNA0417164300")).to be(false)
    end

    it "returns true for a v1 encrypted value" do
      encrypted = described_class.encrypt("NL91ABNA0417164300")
      expect(described_class.encrypted?(encrypted)).to be(true)
    end

    it "returns true for a legacy unversioned encrypted value" do
      box = RbNaCl::SimpleBox.from_secret_key(described_class.send(:encryption_key))
      legacy = Base64.strict_encode64(box.box("NL91ABNA0417164300"))
      expect(described_class.encrypted?(legacy)).to be(true)
    end

    it "returns false for a short Base64 string (not enough bytes)" do
      short = Base64.strict_encode64("tooshort")
      expect(described_class.encrypted?(short)).to be(false)
    end

    it "returns false for a non-Base64 string" do
      expect(described_class.encrypted?("not base64!!!")).to be(false)
    end
  end
end
