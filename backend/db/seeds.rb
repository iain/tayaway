# typed: true
# frozen_string_literal: true

# Seed data for development

now = Time.now
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

puts "Created test user: test@example.com"
