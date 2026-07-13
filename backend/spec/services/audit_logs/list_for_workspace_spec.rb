# frozen_string_literal: true

require "spec_helper"

RSpec.describe AuditLogs::ListForWorkspace do
  let(:workspace) { TestFactories.workspace }
  let(:owner_user) { TestFactories.user(name: "Olive Owner") }
  let(:owner_membership) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: owner_user, role: "owner")[:id]) }

  def entry_at(seconds_ago, **kwargs)
    TestFactories.audit_log_entry(
      workspace: workspace,
      created_at: Time.now - seconds_ago,
      **kwargs
    )
  end

  it "rejects admins and members" do
    %w[admin member].each do |role|
      membership = WorkspaceMembership.find(
        TestFactories.workspace_membership(workspace: workspace, role: role)[:id]
      )

      result = described_class.call(workspace_id: workspace[:id], membership: membership)

      expect(result).to be_failure
      expect(result.failure.code).to eq(:forbidden)
    end
  end

  it "returns not_found for a missing workspace" do
    result = described_class.call(workspace_id: SecureRandom.uuid, membership: owner_membership)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:not_found)
  end

  it "returns entries newest-first with actor names resolved" do
    entry_at(20, actor_user: owner_user, service: "Events::Create", subject_type: "event", subject_id: SecureRandom.uuid)
    entry_at(10, service: "ChoreRosters::SendReminder")
    entry_at(
      5,
      actor_user: owner_user,
      service: "Events::Update",
      outcome: "denied",
      error_code: "forbidden",
      error_message: "not_owner",
      action_params: { "name" => "New name" },
      request_id: "req-123"
    )

    result = described_class.call(workspace_id: workspace[:id], membership: owner_membership)

    expect(result).to be_success
    entries = result.value![:entries]
    expect(entries.map { |e| e[:service] }).to eq(
      ["Events::Update", "ChoreRosters::SendReminder", "Events::Create"]
    )

    denied = entries[0]
    expect(denied).to include(
      outcome: "denied",
      errorCode: "forbidden",
      errorMessage: "not_owner",
      actorKind: "user",
      actorName: "Olive Owner",
      actionParams: { "name" => "New name" },
      requestId: "req-123"
    )
    expect(denied[:createdAt]).to match(/\A\d{4}-\d{2}-\d{2}T/)

    system_entry = entries[1]
    expect(system_entry[:actorKind]).to eq("system")
    expect(system_entry[:actorName]).to be_nil
  end

  it "leaves actorName nil when the actor's user row is gone" do
    ghost = TestFactories.user
    entry_at(10, actor_user: ghost)
    DB[:users].where(id: ghost[:id]).delete

    result = described_class.call(workspace_id: workspace[:id], membership: owner_membership)

    entry = result.value![:entries].first
    expect(entry[:actorUserId]).to eq(ghost[:id])
    expect(entry[:actorName]).to be_nil
  end

  it "excludes entries from other workspaces and entries without a workspace" do
    other_workspace = TestFactories.workspace
    TestFactories.audit_log_entry(workspace: other_workspace, service: "Other::Thing")
    TestFactories.audit_log_entry(workspace: nil, service: "Users::UpdateProfile")
    entry_at(10, service: "Events::Create")

    result = described_class.call(workspace_id: workspace[:id], membership: owner_membership)

    expect(result.value![:entries].map { |e| e[:service] }).to eq(["Events::Create"])
  end

  it "paginates with an opaque cursor" do
    entry_at(40, service: "Page::One")
    entry_at(30, service: "Page::Two")
    entry_at(20, service: "Page::Three")
    entry_at(10, service: "Page::Four")

    first = described_class.call(workspace_id: workspace[:id], membership: owner_membership, limit: 2)
    expect(first.value![:entries].map { |e| e[:service] }).to eq(["Page::Four", "Page::Three"])
    cursor = first.value![:nextCursor]
    expect(cursor).to be_a(String)

    second = described_class.call(workspace_id: workspace[:id], membership: owner_membership, limit: 2, cursor: cursor)
    expect(second.value![:entries].map { |e| e[:service] }).to eq(["Page::Two", "Page::One"])
    expect(second.value![:nextCursor]).to be_nil
  end

  it "paginates stably when entries share a created_at timestamp" do
    shared_time = Time.now - 10
    ids = Array.new(3) { SecureRandom.uuid }
    ids.each do |id|
      TestFactories.audit_log_entry(workspace: workspace, created_at: shared_time, id: id, service: "Tied::#{id[0, 8]}")
    end

    seen = []
    cursor = nil
    3.times do
      result = described_class.call(workspace_id: workspace[:id], membership: owner_membership, limit: 1, cursor: cursor)
      seen.concat(result.value![:entries].map { |e| e[:id] })
      cursor = result.value![:nextCursor]
    end

    expect(seen).to match_array(ids)
    expect(cursor).to be_nil
  end

  it "omits nextCursor when the last page is exactly full" do
    entry_at(20, service: "Only::One")
    entry_at(10, service: "Only::Two")

    result = described_class.call(workspace_id: workspace[:id], membership: owner_membership, limit: 2)

    expect(result.value![:entries].length).to eq(2)
    expect(result.value![:nextCursor]).to be_nil
  end

  it "rejects a malformed cursor" do
    result = described_class.call(workspace_id: workspace[:id], membership: owner_membership, cursor: "not-a-cursor")

    expect(result).to be_failure
    expect(result.failure.code).to eq(:validation_error)
  end
end
