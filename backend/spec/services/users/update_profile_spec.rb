# frozen_string_literal: true

require "spec_helper"

RSpec.describe Users::UpdateProfile do
  it "returns failure when user tries to update another user" do
    user = TestFactories.user
    other_user = TestFactories.user

    result = described_class.call(
      user_id: other_user[:id],
      current_user_id: user[:id],
      name: "New Name"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
    expect(result.failure.http_status).to eq(403)
  end

  it "returns failure when name is empty" do
    user = TestFactories.user

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: ""
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "returns failure when name is blank" do
    user = TestFactories.user

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "   "
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "succeeds when name is nil (contact-only update)" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Keep This")
    TestFactories.workspace_membership(workspace: workspace, user: user)

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: nil,
      phone_number: "+31612345678"
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:name]).to eq("Keep This")
    expect(updated_member[:phoneNumber]).to eq("+31612345678")
  end

  it "updates user name" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Original")
    TestFactories.workspace_membership(workspace: workspace, user: user)

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Updated Name"
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:name]).to eq("Updated Name")
  end

  it "updates phone number" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      phone_number: "+31612345678"
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:phoneNumber]).to eq("+31612345678")
  end

  it "updates birthday" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      birthday: "1990-06-15"
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:birthday]).to eq("1990-06-15")
  end

  it "returns failure for invalid birthday format" do
    user = TestFactories.user(name: "Test")

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      birthday: "not-a-date"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid birthday format")
  end

  it "updates location with coordinates" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      location_name: "Berlin, Germany",
      latitude: 52.52,
      longitude: 13.405
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:locationName]).to eq("Berlin, Germany")
    expect(updated_member[:latitude]).to be_within(0.001).of(52.52)
    expect(updated_member[:longitude]).to be_within(0.001).of(13.405)
  end

  it "clears phone number when blank" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)
    DB[:users].where(id: user[:id]).update(phone_number: "+31612345678")

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      phone_number: ""
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:phoneNumber]).to be_nil
  end

  it "updates all contact fields at once" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Full Update",
      phone_number: "+49301234567",
      birthday: "1985-12-25",
      location_name: "Munich, Germany",
      latitude: 48.1351,
      longitude: 11.582
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:name]).to eq("Full Update")
    expect(updated_member[:phoneNumber]).to eq("+49301234567")
    expect(updated_member[:birthday]).to eq("1985-12-25")
    expect(updated_member[:locationName]).to eq("Munich, Germany")
    expect(updated_member[:latitude]).to be_within(0.001).of(48.1351)
    expect(updated_member[:longitude]).to be_within(0.001).of(11.582)
  end

  it "leaves existing fields unchanged when not provided" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)
    DB[:users].where(id: user[:id]).update(
      phone_number: "+31612345678",
      birthday: Date.new(1990, 6, 15),
      location_name: "Amsterdam",
      location_coordinates: Sequel.lit("point(4.9041, 52.3676)")
    )

    # Only update name, don't pass contact fields
    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "New Name"
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:name]).to eq("New Name")
    expect(updated_member[:phoneNumber]).to eq("+31612345678")
    expect(updated_member[:birthday]).to eq("1990-06-15")
    expect(updated_member[:locationName]).to eq("Amsterdam")
    expect(updated_member[:latitude]).to be_within(0.001).of(52.3676)
    expect(updated_member[:longitude]).to be_within(0.001).of(4.9041)
  end

  it "clears birthday when blank" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)
    DB[:users].where(id: user[:id]).update(birthday: Date.new(1990, 6, 15))

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      birthday: ""
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:birthday]).to be_nil
  end

  it "strips whitespace from phone number" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      phone_number: "  +31612345678  "
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:phoneNumber]).to eq("+31612345678")
  end

  it "strips whitespace from location name" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      location_name: "  Berlin, Germany  ",
      latitude: 52.52,
      longitude: 13.405
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:locationName]).to eq("Berlin, Germany")
  end

  it "returns failure when user not found" do
    user = TestFactories.user

    result = described_class.call(
      user_id: "00000000-0000-0000-0000-000000000000",
      current_user_id: user[:id],
      name: "Test"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("User not found")
    expect(result.failure.http_status).to eq(404)
  end

  it "updates IBAN" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      iban: "NL91ABNA0417164300"
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:hasIban]).to be true
  end

  it "normalizes IBAN by stripping spaces and uppercasing" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      iban: "nl91 abna 0417 1643 00"
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:hasIban]).to be true
  end

  it "clears IBAN when blank" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)
    DB[:users].where(id: user[:id]).update(iban: "NL91ABNA0417164300")

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      iban: ""
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:hasIban]).to be false
  end

  it "returns failure for invalid IBAN format" do
    user = TestFactories.user(name: "Test")

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      iban: "INVALID"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid IBAN format")
  end

  it "returns failure for IBAN with invalid checksum" do
    user = TestFactories.user(name: "Test")

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      iban: "NL00ABNA0417164300"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid IBAN checksum")
  end

  it "leaves IBAN unchanged when not provided" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)
    DB[:users].where(id: user[:id]).update(iban: "NL91ABNA0417164300")

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Updated"
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:hasIban]).to be true
  end

  it "clears location when blank" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)
    DB[:users].where(id: user[:id]).update(
      location_name: "Berlin",
      location_coordinates: Sequel.lit("point(13.405, 52.52)")
    )

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      location_name: ""
    )

    expect(result.success?).to be true
    updated_member = result.value![:objects].find { |o| o[:objectType] == "member" }
    expect(updated_member[:locationName]).to be_nil
    expect(updated_member[:latitude]).to be_nil
    expect(updated_member[:longitude]).to be_nil
  end

  it "returns failure when latitude is out of range" do
    user = TestFactories.user(name: "Test")

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      location_name: "Nowhere",
      latitude: 91.0,
      longitude: 0.0
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Latitude must be between -90 and 90")
  end

  it "returns failure when longitude is out of range" do
    user = TestFactories.user(name: "Test")

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      location_name: "Nowhere",
      latitude: 0.0,
      longitude: 181.0
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Longitude must be between -180 and 180")
  end

  it "returns failure for birthday too far in the past" do
    user = TestFactories.user(name: "Test")

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      birthday: "1899-12-31"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Birthday is too far in the past")
  end

  it "returns failure for birthday in the future" do
    user = TestFactories.user(name: "Test")
    future = (Date.today + 1).iso8601

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Test",
      birthday: future
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Birthday cannot be in the future")
  end

  it "logs info when profile is updated" do
    workspace = TestFactories.workspace
    user = TestFactories.user(name: "Test")
    TestFactories.workspace_membership(workspace: workspace, user: user)
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(user_id: user[:id], current_user_id: user[:id], name: "Updated")

    expect(logged_messages).to include(a_string_including("[Users::UpdateProfile]"))
  end
end
