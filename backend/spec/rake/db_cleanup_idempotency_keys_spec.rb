# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "rake db:cleanup_idempotency_keys" do
  let(:fake_dataset) { instance_double(Sequel::Dataset) }

  let(:rake) do
    app = Rake::Application.new
    Rake.application = app
    load File.expand_path("../../Rakefile", __dir__)
    app
  end

  before do
    allow(DB).to receive(:[]).with(:idempotency_keys).and_return(fake_dataset)
    allow(fake_dataset).to receive_messages(where: fake_dataset, delete: 0)
  end

  after do
    Rake.application = Rake::Application.new
    ENV.delete("IDEMPOTENCY_KEY_TTL_HOURS")
  end

  it "deletes rows filtered by created_at" do
    rake["db:cleanup_idempotency_keys"].invoke

    expect(fake_dataset).to have_received(:where)
    expect(fake_dataset).to have_received(:delete)
  end

  it "prints a summary with the number of deleted rows" do
    allow(fake_dataset).to receive(:delete).and_return(7)

    expect { rake["db:cleanup_idempotency_keys"].invoke }.to output(/Deleted 7 idempotency_keys rows older than 24 hours/).to_stdout
  end

  it "uses the default TTL of 24 hours when env var is not set" do
    expect { rake["db:cleanup_idempotency_keys"].invoke }.to output(/older than 24 hours/).to_stdout
  end

  it "respects the IDEMPOTENCY_KEY_TTL_HOURS env var" do
    ENV["IDEMPOTENCY_KEY_TTL_HOURS"] = "48"

    expect { rake["db:cleanup_idempotency_keys"].invoke }.to output(/older than 48 hours/).to_stdout
  end
end
