# typed: true
# frozen_string_literal: true

require_relative "../config/environment"

# Seed data for development

now = Time.now
user_id = SecureRandom.uuid

DB[:users].insert_conflict(
  target: :email,
  update: { name: "Test User", updated_at: now }
).insert(
  id: user_id,
  email: "test@example.com",
  name: "Test User",
  created_at: now,
  updated_at: now
)

# Get the actual user ID (in case of conflict, the insert returns nothing)
user = DB[:users].where(email: "test@example.com").first
user_id = user[:id]

puts "Created test user: test@example.com"

# Create a default workspace if it doesn't exist
workspace = DB[:workspaces].where(name: "Test Workspace").first
unless workspace
  workspace_id = SecureRandom.uuid
  DB[:workspaces].insert(
    id: workspace_id,
    name: "Test Workspace",
    created_at: now,
    updated_at: now
  )
  workspace = DB[:workspaces].where(id: workspace_id).first
  puts "Created workspace: Test Workspace"
else
  puts "Workspace already exists: Test Workspace"
end
workspace_id = workspace[:id]

# Add user as workspace member (owner)
existing_membership = DB[:workspace_memberships].where(
  workspace_id: workspace_id,
  user_id: user_id
).first

unless existing_membership
  DB[:workspace_memberships].insert(
    id: SecureRandom.uuid,
    workspace_id: workspace_id,
    user_id: user_id,
    role: "owner",
    created_at: now
  )
  puts "Added test user as workspace owner"
end
