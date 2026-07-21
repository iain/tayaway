# frozen_string_literal: true

ENV["MISE_ENV"] = "test"

module Warning
  def self.warn(msg, **)
    super unless msg.include?("redefining 'object_id'")
  end
end

require_relative "../config/environment"
require_relative "support/test_database_guard"
TestDatabaseGuard.enforce!(DB.opts[:database])

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

  # Rack::Test requests advertise a supported protocol version by default,
  # like any real client build — otherwise every route spec would trip the
  # 426 gate now that MIN_SUPPORTED_VERSION has moved past 0. A spec that
  # needs a versionless request (the gate specs) passes the env key
  # explicitly with a nil value: `get "/x", {}, { "HTTP_X_CLIENT_VERSION" => nil }`.
  define_method(:app) do
    inner = App.freeze.app
    lambda do |env|
      unless env.key?("HTTP_X_CLIENT_VERSION")
        env["HTTP_X_CLIENT_VERSION"] = ClientProtocol::MIN_SUPPORTED_VERSION.to_s
      end
      inner.call(env)
    end
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
