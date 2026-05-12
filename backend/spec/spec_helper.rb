# frozen_string_literal: true

ENV["RACK_ENV"] = "test"

module Warning
  def self.warn(msg, **)
    super unless msg.include?("redefining 'object_id'")
  end
end

require_relative "../config/environment"
require "rack/test"
require "database_cleaner/sequel"
require_relative "support/test_factories"
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.include Rack::Test::Methods

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  define_method(:app) do
    App.freeze.app
  end

  config.before(:suite) do
    DatabaseCleaner[:sequel].strategy = :transaction
    DatabaseCleaner[:sequel].clean_with(:truncation)
  end

  config.before do
    TestFactories.reset_sequences!
    Mail::TestMailer.deliveries.clear
  end

  config.around do |example|
    DatabaseCleaner[:sequel].cleaning do
      example.run
    end
  end

  config.around(:each, :silence_stdout) do |example|
    original = $stdout
    $stdout = StringIO.new
    begin
      example.run
    ensure
      $stdout = original
    end
  end
end
