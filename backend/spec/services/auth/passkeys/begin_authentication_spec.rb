# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::Passkeys::BeginAuthentication do
  it "returns WebAuthn request options" do
    result = described_class.call

    expect(result.success?).to be true
    value = result.value!
    expect(value[:options]).to include(:challenge, :rpId, :timeout)
    expect(value[:challengeToken]).to be_a(String)
  end
end
