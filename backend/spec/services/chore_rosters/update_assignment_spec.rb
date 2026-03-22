# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::UpdateAssignment do
  let(:user) { TestFactories.user }
  let(:other_user) { TestFactories.user(name: "Other") }
  let(:workspace) { TestFactories.workspace }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: e[:id]).update(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 7))
    DB[:events].where(id: e[:id]).first
  end
  let(:roster) { TestFactories.chore_roster(event: event, user: user) }
  let(:chore) { TestFactories.chore(chore_roster: roster, name: "Cooking") }
  let(:assignment) { TestFactories.chore_assignment(chore: chore, user: user, date: Date.new(2026, 3, 1), pinned: true) }

  it "updates the note" do
    result = described_class.call(
      assignment_id: assignment[:id],
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      note: "Pizza night"
    )

    expect(result.success?).to be true
    updated = result.value![:objects].find { |o| o[:objectType] == "choreAssignment" }
    expect(updated[:note]).to eq("Pizza night")
  end

  it "reassigns to a different user" do
    result = described_class.call(
      assignment_id: assignment[:id],
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      user_id: other_user[:id].to_s
    )

    expect(result.success?).to be true
    updated = result.value![:objects].find { |o| o[:objectType] == "choreAssignment" }
    expect(updated[:userId]).to eq(other_user[:id].to_s)
  end

  it "returns the parent chore in response" do
    result = described_class.call(
      assignment_id: assignment[:id],
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      note: "Updated"
    )

    chore_obj = result.value![:objects].find { |o| o[:objectType] == "chore" }
    expect(chore_obj).not_to be_nil
  end

  it "clears an existing note when an empty string is given" do
    DB[:chore_assignments].where(id: assignment[:id]).update(note: "Old note")

    result = described_class.call(
      assignment_id: assignment[:id],
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      note: ""
    )

    expect(result.success?).to be true
    updated = result.value![:objects].find { |o| o[:objectType] == "choreAssignment" }
    expect(updated[:note]).to eq("")
  end

  it "fails when no changes provided" do
    result = described_class.call(
      assignment_id: assignment[:id],
      roster_id: roster[:id],
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to include("No changes")
  end

  it "fails for nonexistent assignment" do
    result = described_class.call(
      assignment_id: SecureRandom.uuid,
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      note: "test"
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
  end
end
