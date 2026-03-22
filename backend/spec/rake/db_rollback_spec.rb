# typed: false
# frozen_string_literal: true

require "spec_helper"
require "rake"

Sequel.extension :migration

RSpec.describe "rake db:rollback" do
  let(:rake) do
    app = Rake::Application.new
    Rake.application = app
    load File.expand_path("../../Rakefile", __dir__)
    app
  end
  let(:fake_migrator) { instance_double(Sequel::IntegerMigrator, current: 5) }

  after do
    Rake.application = Rake::Application.new
  end

  before do
    allow(Sequel::IntegerMigrator).to receive(:new).and_return(fake_migrator)
  end

  it "rolls back to the version before the current one" do
    run_calls = []
    allow(Sequel::Migrator).to receive(:run) do |_db, _dir, target: nil|
      run_calls << target
    end

    rake["db:rollback"].invoke

    # Current version is 5 so target should be 4 (5 - 1).
    expect(run_calls).to eq([4])
  end

  it "does not call Sequel::Migrator.run with target: 0 to read the current version" do
    targets_called = []
    allow(Sequel::Migrator).to receive(:run) do |_db, _dir, target: nil|
      targets_called << target
    end

    rake["db:rollback"].invoke

    expect(targets_called).not_to include(0),
                                  "db:rollback must not call Migrator.run(target: 0), which would destroy all tables"
  end
end
