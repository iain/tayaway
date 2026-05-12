# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "rake db:cleanup_audit_log_entries", :silence_stdout do
  let(:rake) do
    app = Rake::Application.new
    Rake.application = app
    load File.expand_path("../../Rakefile", __dir__)
    app
  end

  after do
    Rake.application = Rake::Application.new
    ENV.delete("AUDIT_LOG_RETENTION_DAYS")
  end

  def insert_entry(age_days:, service: "Events::Create")
    DB[:audit_log_entries].insert(
      service: service,
      actor_kind: "system",
      outcome: "success",
      action_params: Sequel.pg_jsonb({}),
      created_at: Time.now - (age_days * 24 * 60 * 60)
    )
  end

  it "deletes rows older than the retention window and keeps fresh ones" do
    insert_entry(age_days: 1, service: "Fresh")
    insert_entry(age_days: 400, service: "Stale")

    rake["db:cleanup_audit_log_entries"].invoke

    services = DB[:audit_log_entries].select_map(:service)
    expect(services).to include("Fresh")
    expect(services).not_to include("Stale")
  end

  it "respects AUDIT_LOG_RETENTION_DAYS" do
    ENV["AUDIT_LOG_RETENTION_DAYS"] = "30"

    insert_entry(age_days: 10, service: "Inside")
    insert_entry(age_days: 60, service: "Outside")

    rake["db:cleanup_audit_log_entries"].invoke

    services = DB[:audit_log_entries].select_map(:service)
    expect(services).to include("Inside")
    expect(services).not_to include("Outside")
  end
end
