# frozen_string_literal: true

require "spec_helper"

RSpec.describe Encryption do
  let(:user_id) { SecureRandom.uuid }

  describe ".encrypt / .decrypt" do
    it "round-trips a plaintext value" do
      iban = "NL91ABNA0417164300"
      encrypted = described_class.encrypt(iban, user_id: user_id)
      expect(described_class.decrypt(encrypted, user_id: user_id)).to eq(iban)
    end

    it "produces different ciphertext on each call (random nonce)" do
      iban = "DE89370400440532013000"
      first = described_class.encrypt(iban, user_id: user_id)
      second = described_class.encrypt(iban, user_id: user_id)
      expect(first).not_to eq(second)
    end

    it "produces Base64-encoded output with v2 prefix" do
      encrypted = described_class.encrypt("GB29NWBK60161331926819", user_id: user_id)
      raw = Base64.strict_decode64(encrypted)
      expect(raw.getbyte(0)).to eq(0x02)
    end

    it "fails to decrypt when user_id does not match (AAD mismatch)" do
      encrypted = described_class.encrypt("NL91ABNA0417164300", user_id: user_id)
      expect {
        described_class.decrypt(encrypted, user_id: SecureRandom.uuid)
      }.to raise_error(RbNaCl::CryptoError)
    end
  end

  describe ".encrypted?" do
    it "returns false for a plaintext IBAN" do
      expect(described_class.encrypted?("NL91ABNA0417164300")).to be(false)
    end

    it "returns true for an encrypted value" do
      encrypted = described_class.encrypt("NL91ABNA0417164300", user_id: user_id)
      expect(described_class.encrypted?(encrypted)).to be(true)
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
