# typed: false
# frozen_string_literal: true

require "securerandom"

FactoryBot.define do
  factory :user, class: Hash do
    transient do
      id { SecureRandom.uuid }
    end
    sequence(:email) { |n| "user#{n}@example.com" }
    name { "Test User" }

    initialize_with do
      now = Time.now
      DB[:users].insert(
        id: id,
        email: email,
        name: name,
        created_at: now,
        updated_at: now
      )
      DB[:users].where(id: id).first
    end

    to_create { |instance| instance }
  end

  factory :event, class: Hash do
    transient do
      id { SecureRandom.uuid }
    end
    user
    sequence(:name) { |n| "Event #{n}" }
    description { "Test description" }

    initialize_with do
      now = Time.now
      DB[:events].insert(
        id: id,
        user_id: user[:id],
        name: name,
        description: description,
        created_at: now,
        updated_at: now
      )
      DB[:events].where(id: id).first
    end

    to_create { |instance| instance }
  end

  factory :date_range, class: Hash do
    transient do
      id { SecureRandom.uuid }
    end
    event
    start_date { Date.today }
    end_date { Date.today + 7 }

    initialize_with do
      now = Time.now
      DB[:date_ranges].insert(
        id: id,
        event_id: event[:id],
        start_date: start_date,
        end_date: end_date,
        created_at: now,
        updated_at: now
      )
      DB[:date_ranges].where(id: id).first
    end

    to_create { |instance| instance }
  end

  factory :vote, class: Hash do
    transient do
      id { SecureRandom.uuid }
    end
    date_range
    user
    response { "yes" }
    comment { nil }

    initialize_with do
      now = Time.now
      DB[:votes].insert(
        id: id,
        date_range_id: date_range[:id],
        user_id: user[:id],
        response: response,
        comment: comment,
        created_at: now,
        updated_at: now
      )
      DB[:votes].where(id: id).first
    end

    to_create { |instance| instance }
  end

  factory :session, class: Hash do
    transient do
      id { SecureRandom.uuid }
    end
    user
    token { SecureRandom.hex(32) }
    expires_at { Time.now + (30 * 24 * 60 * 60) }

    initialize_with do
      now = Time.now
      DB[:sessions].insert(
        id: id,
        user_id: user[:id],
        token: token,
        expires_at: expires_at,
        created_at: now
      )
      DB[:sessions].where(id: id).first
    end

    to_create { |instance| instance }
  end

  factory :magic_link_token, class: Hash do
    transient do
      id { SecureRandom.uuid }
    end
    user
    token { SecureRandom.hex(32) }
    email { nil }
    expires_at { Time.now + (15 * 60) }
    used_at { nil }

    initialize_with do
      now = Time.now
      actual_email = email || user[:email]
      DB[:magic_link_tokens].insert(
        id: id,
        user_id: user[:id],
        token: token,
        email: actual_email,
        expires_at: expires_at,
        used_at: used_at,
        created_at: now
      )
      DB[:magic_link_tokens].where(id: id).first
    end

    to_create { |instance| instance }
  end
end
