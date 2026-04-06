# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::Passkeys::ChallengeValidation do
  # Create a test class that includes the module
  let(:validator) do
    Class.new do
      include Auth::Passkeys::ChallengeValidation
    end.new
  end

  let(:user) { TestFactories.user }

  describe "#validate_challenge_inputs" do
    it "fails when challenge_token is nil" do
      result = validator.validate_challenge_inputs(nil, { "id" => "cred" })
      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Challenge token is required")
    end

    it "fails when challenge_token is empty" do
      result = validator.validate_challenge_inputs("", { "id" => "cred" })
      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Challenge token is required")
    end

    it "fails when credential is nil" do
      token = Auth::Token.encode_webauthn_challenge(challenge: "test")
      result = validator.validate_challenge_inputs(token, nil)
      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Credential is required")
    end

    it "fails when credential is empty" do
      token = Auth::Token.encode_webauthn_challenge(challenge: "test")
      result = validator.validate_challenge_inputs(token, {})
      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Credential is required")
    end

    it "fails when challenge_token is expired or invalid" do
      result = validator.validate_challenge_inputs("invalid.jwt.token", { "id" => "cred" })
      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Invalid or expired challenge")
    end

    it "succeeds with valid inputs" do
      challenge = SecureRandom.hex(16)
      token = Auth::Token.encode_webauthn_challenge(challenge: challenge)
      result = validator.validate_challenge_inputs(token, { "id" => "cred" })
      expect(result.success?).to be true
      expect(result.value!).to eq(challenge)
    end

    context "with user_id binding" do
      it "fails when user_id does not match token subject" do
        challenge = SecureRandom.hex(16)
        token = Auth::Token.encode_webauthn_challenge(challenge: challenge, user_id: user[:id])
        result = validator.validate_challenge_inputs(token, { "id" => "cred" }, user_id: "different-user")
        expect(result.failure?).to be true
        expect(result.failure.message).to eq("Invalid or expired challenge")
      end

      it "succeeds when user_id matches token subject" do
        challenge = SecureRandom.hex(16)
        token = Auth::Token.encode_webauthn_challenge(challenge: challenge, user_id: user[:id])
        result = validator.validate_challenge_inputs(token, { "id" => "cred" }, user_id: user[:id])
        expect(result.success?).to be true
        expect(result.value!).to eq(challenge)
      end
    end
  end
end
