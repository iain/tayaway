# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::DeleteAssignment do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: e[:id]).update(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 7))
    DB[:events].where(id: e[:id]).first
  end
  let(:roster) { TestFactories.chore_roster(event: event, user: user) }
  let(:chore) { TestFactories.chore(chore_roster: roster, name: "Cooking") }
  let(:assignment) { TestFactories.chore_assignment(chore: chore, user: user, date: Date.new(2026, 3, 1), pinned: true) }

  it "deletes the assignment" do
    assignment_id = assignment[:id]

    result = described_class.call(assignment_id: assignment_id, workspace_id: workspace[:id])

    expect(result.success?).to be true
    expect(DB[:chore_assignments].where(id: assignment_id).count).to eq(0)
  end

  it "tracks deletion in deleted_items" do
    assignment_id = assignment[:id]

    described_class.call(assignment_id: assignment_id, workspace_id: workspace[:id])

    expect(DB[:deleted_items].where(object_type: "chore_assignment", object_id: assignment_id).count).to eq(1)
  end

  it "returns the deleted item in response" do
    result = described_class.call(assignment_id: assignment[:id], workspace_id: workspace[:id])

    deleted = result.value![:deleted]
    expect(deleted.length).to eq(1)
    expect(deleted.first[:objectType]).to eq("choreAssignment")
    expect(deleted.first[:id]).to eq(assignment[:id].to_s)
  end

  it "returns the parent chore in response" do
    result = described_class.call(assignment_id: assignment[:id], workspace_id: workspace[:id])

    chore_obj = result.value![:objects].find { |o| o[:objectType] == "chore" }
    expect(chore_obj).not_to be_nil
    expect(chore_obj[:assignmentIds]).not_to include(assignment[:id].to_s)
  end

  it "fails for nonexistent assignment" do
    result = described_class.call(assignment_id: SecureRandom.uuid, workspace_id: workspace[:id])

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
  end
end
