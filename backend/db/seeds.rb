# typed: true
# frozen_string_literal: true

require_relative "../config/environment"

# Seed data for development

now = Time.now

# Deterministic UUID for workspace (no natural key available)
WORKSPACE_ID = "00000000-0000-0000-0000-000000000001"

# Upsert user by email
DB[:users].insert_conflict(
  target: :email,
  update: { name: "Test User", updated_at: now }
).insert(
  id: SecureRandom.uuid,
  email: "test@example.com",
  name: "Test User",
  created_at: now,
  updated_at: now
)
user_id = DB[:users].where(email: "test@example.com").get(:id)
puts "Upserted test user: test@example.com"

# Upsert workspace by ID
DB[:workspaces].insert_conflict(
  target: :id,
  update: { name: "Test Workspace", updated_at: now }
).insert(
  id: WORKSPACE_ID,
  name: "Test Workspace",
  created_at: now,
  updated_at: now
)
puts "Upserted workspace: Test Workspace"

# Upsert membership using IDs from above
DB[:workspace_memberships].insert_conflict(
  target: [:workspace_id, :user_id],
  update: { role: "owner" }
).insert(
  id: SecureRandom.uuid,
  workspace_id: WORKSPACE_ID,
  user_id: user_id,
  role: "owner",
  created_at: now
)
puts "Upserted test user as workspace owner"
