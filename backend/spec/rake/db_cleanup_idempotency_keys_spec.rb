# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "rake db:cleanup_idempotency_keys", :silence_stdout do
  let(:user) { TestFactories.user }

  let(:rake) do
    app = Rake::Application.new
    Rake.application = app
    load File.expand_path("../../Rakefile", __dir__)
    app
  end

  after do
    Rake.application = Rake::Application.new
    ENV.delete("IDEMPOTENCY_KEY_TTL_HOURS")
  end

  def insert_key(age_hours:, key: SecureRandom.uuid)
    DB[:idempotency_keys].insert(
      user_id: user[:id],
      idempotency_key_hash: Idempotency.digest(key),
      request_fingerprint: "fp",
      response_status: 200,
      response_body: "{}",
      created_at: Time.now - (age_hours * 60 * 60)
    )
    Idempotency.digest(key)
  end

  it "deletes rows older than the TTL and keeps fresh ones" do
    fresh = insert_key(age_hours: 1)
    stale = insert_key(age_hours: 48)

    rake["db:cleanup_idempotency_keys"].invoke

    remaining = DB[:idempotency_keys].select_map(:idempotency_key_hash)
    expect(remaining).to include(fresh)
    expect(remaining).not_to include(stale)
  end

  it "respects the IDEMPOTENCY_KEY_TTL_HOURS env var" do
    ENV["IDEMPOTENCY_KEY_TTL_HOURS"] = "72"

    inside_window = insert_key(age_hours: 48)
    outside_window = insert_key(age_hours: 96)

    rake["db:cleanup_idempotency_keys"].invoke

    remaining = DB[:idempotency_keys].select_map(:idempotency_key_hash)
    expect(remaining).to include(inside_window)
    expect(remaining).not_to include(outside_window)
  end
end
