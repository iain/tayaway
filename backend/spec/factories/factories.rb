# typed: false
# frozen_string_literal: true

FactoryBot.define do
  to_create(&:save)

  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { "Test User" }
  end

  factory :event do
    association :user
    sequence(:name) { |n| "Event #{n}" }
    description { "Test description" }
  end

  factory :date_range do
    association :event
    start_date { Date.today }
    end_date { Date.today + 7 }
  end

  factory :vote do
    association :date_range
    association :user
    response { "yes" }
  end

  factory :session do
    association :user
    token { SecureRandom.hex(32) }
    expires_at { Time.now + (30 * 24 * 60 * 60) }
  end

  factory :magic_link_token do
    association :user
    token { SecureRandom.hex(32) }
    email { |token| token.user.email }
    expires_at { Time.now + (15 * 60) }
  end
end
