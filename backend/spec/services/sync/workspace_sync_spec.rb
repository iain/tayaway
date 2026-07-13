# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sync::WorkspaceSync do
  let(:workspace) { TestFactories.workspace(name: "My Workspace") }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  it "returns empty response when workspace not found" do
    missing_id = SecureRandom.uuid
    result = described_class.call(workspace_id: missing_id)

    expect(result[:objects]).to eq([])
    expect(result[:deleted]).to eq([])
    expect(result[:syncType]).to eq("full")
    expect(result[:syncedAt]).not_to be_nil
    expect(result[:workspaceId]).to eq(missing_id)
  end

  # The client routes each sync payload into a pool scope. Without the id on
  # the envelope it has to guess from "current workspace at receive time",
  # which misroutes syncs that land mid-switch or via the new-member
  # bootstrap — a full sync then wipes the wrong scope.
  it "tags the payload with the workspace id" do
    result = described_class.call(workspace_id: workspace[:id])

    expect(result[:workspaceId]).to eq(workspace[:id].to_s)
  end

  it "returns full sync with workspace object" do
    result = described_class.call(workspace_id: workspace[:id])

    expect(result[:syncType]).to eq("full")
    ws_obj = result[:objects].find { |o| o[:objectType] == "workspace" }
    expect(ws_obj).not_to be_nil
    expect(ws_obj[:name]).to eq("My Workspace")
  end

  it "includes members in the response" do
    result = described_class.call(workspace_id: workspace[:id])

    member_obj = result[:objects].find { |o| o[:objectType] == "member" }
    expect(member_obj).not_to be_nil
    expect(member_obj[:userId]).to eq(user[:id].to_s)
  end

  it "includes events in the response" do
    TestFactories.event(workspace: workspace, user: user, name: "Birthday Party")

    result = described_class.call(workspace_id: workspace[:id])

    event_obj = result[:objects].find { |o| o[:objectType] == "event" }
    expect(event_obj).not_to be_nil
    expect(event_obj[:name]).to eq("Birthday Party")
  end

  # Tombstones are stored with the registry key (snake_case) but the client
  # pool is keyed by client types (camelCase) — cascadeRemove silently no-ops
  # on an unknown type, so the payload must carry client types or multi-word
  # deletions never prune.
  it "returns deleted items on partial sync, typed for the client" do
    event = TestFactories.event(workspace: workspace, user: user)
    event_id = event[:id].to_s
    assignment_id = SecureRandom.uuid
    since = Time.now - 60

    DB[:deleted_items].multi_insert([
                                      { workspace_id: workspace[:id], object_type: "event",
                                        object_id: event_id, deleted_at: Time.now },
                                      { workspace_id: workspace[:id], object_type: "chore_assignment",
                                        object_id: assignment_id, deleted_at: Time.now }
                                    ]
                                   )

    result = described_class.call(workspace_id: workspace[:id], since: since)

    expect(result[:syncType]).to eq("partial")
    expect(result[:deleted]).to include(hash_including(objectType: "event", id: event_id))
    expect(result[:deleted]).to include(hash_including(objectType: "choreAssignment", id: assignment_id))
  end

  it "forces a full sync when since is older than retention period" do
    old_since = Time.now - (8 * 24 * 60 * 60) # 8 days ago

    result = described_class.call(workspace_id: workspace[:id], since: old_since)

    expect(result[:syncType]).to eq("full")
    expect(result[:deleted]).to eq([])
  end

  it "performs a partial sync when since is within retention period" do
    since = Time.now - 60

    result = described_class.call(workspace_id: workspace[:id], since: since)

    expect(result[:syncType]).to eq("partial")
  end

  # `updated_at` is stamped before COMMIT makes the row visible, so a row can
  # be older than a cursor the client legitimately holds. The overlap window
  # resends the recent past; the client merges duplicates idempotently.
  it "resends changes and deletions from just before since (overlap window)" do
    event = TestFactories.event(workspace: workspace, user: user)
    since = Time.now
    DB[:events].where(id: event[:id]).update(updated_at: since - 30)
    DB[:deleted_items].insert(
      workspace_id: workspace[:id],
      object_type: "task_list",
      object_id: SecureRandom.uuid,
      deleted_at: since - 30
    )

    result = described_class.call(workspace_id: workspace[:id], since: since)

    expect(result[:syncType]).to eq("partial")
    expect(result[:objects].map { |o| o[:id] }).to include(event[:id].to_s)
    expect(result[:deleted]).to include(hash_including(objectType: "taskList"))
  end

  # Behavioral guard for the registry-driven dispatch: every type in
  # ObjectRegistry (aside from workspace / member, which are handled outside
  # the iteration) must at minimum reach its model's changed_since. Catches
  # a new type being added without WorkspaceSync picking it up, which would
  # otherwise only surface at runtime on a full sync of that type.
  it "iterates every workspace-audience registered type via ObjectRegistry::TYPES" do
    called_keys = []
    ObjectRegistry::TYPES.each do |entry|
      next if %w[workspace member].include?(entry.key)
      next unless entry.workspace_audience?

      model = Object.const_get(entry.model)
      allow(model).to receive(:changed_since).and_wrap_original do |orig, *args|
        called_keys << entry.key
        orig.call(*args)
      end
    end

    described_class.call(workspace_id: workspace[:id])

    expected = ObjectRegistry::TYPES.select(&:workspace_audience?).map(&:key) - %w[workspace member]
    missing = expected - called_keys
    expect(missing).to be_empty, "WorkspaceSync skipped registry entries: #{missing.inspect}"
  end

  it "skips user-audience registered types (they ride a per-user broadcast path)" do
    # User-audience models (e.g. Notification) deliberately don't implement
    # `changed_since(workspace_id, ...)` — they aren't owned by a workspace.
    # If WorkspaceSync ever forgets to filter by audience, the iteration will
    # raise NoMethodError. Asserting "doesn't blow up" is the regression test.
    user_audience_entries = ObjectRegistry::TYPES.select(&:user_audience?)
    expect(user_audience_entries).not_to be_empty, "no user-audience entries to assert against"

    expect { described_class.call(workspace_id: workspace[:id]) }.not_to raise_error
  end
end
