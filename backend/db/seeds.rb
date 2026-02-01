# typed: true
# frozen_string_literal: true

# Seed data for development

User.find_or_create(email: "test@example.com") do |user|
  user.name = "Test User"
end

puts "Created test user: test@example.com"
