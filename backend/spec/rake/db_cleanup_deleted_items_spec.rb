# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "rake db:cleanup_deleted_items" do
  let(:fake_dataset) { instance_double(Sequel::Dataset) }

  let(:rake) do
    app = Rake::Application.new
    Rake.application = app
    load File.expand_path("../../Rakefile", __dir__)
    app
  end

  before do
    allow(DB).to receive(:[]).with(:deleted_items).and_return(fake_dataset)
    allow(fake_dataset).to receive_messages(where: fake_dataset, delete: 0)
  end

  after do
    Rake.application = Rake::Application.new
    ENV.delete("DELETED_ITEMS_RETENTION_DAYS")
  end

  it "deletes rows filtered by deleted_at" do
    rake["db:cleanup_deleted_items"].invoke

    expect(fake_dataset).to have_received(:where)
    expect(fake_dataset).to have_received(:delete)
  end

  it "prints a summary with the number of deleted rows" do
    allow(fake_dataset).to receive(:delete).and_return(42)

    expect { rake["db:cleanup_deleted_items"].invoke }.to output(/Deleted 42 deleted_items rows older than 7 days/).to_stdout
  end

  it "uses the default retention period of 7 days when env var is not set" do
    ENV.delete("DELETED_ITEMS_RETENTION_DAYS")

    expect { rake["db:cleanup_deleted_items"].invoke }.to output(/older than 7 days/).to_stdout
  end

  it "respects the DELETED_ITEMS_RETENTION_DAYS env var" do
    ENV["DELETED_ITEMS_RETENTION_DAYS"] = "30"

    expect { rake["db:cleanup_deleted_items"].invoke }.to output(/older than 30 days/).to_stdout
  end
end
