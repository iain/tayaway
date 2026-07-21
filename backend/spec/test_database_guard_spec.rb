# frozen_string_literal: true

require "spec_helper"

RSpec.describe TestDatabaseGuard do
  it "accepts only the dedicated test database" do
    expect(described_class.test_database?("tayaway_test")).to be true
    expect(described_class.test_database?("tayaway_development")).to be false
    expect(described_class.test_database?(nil)).to be false
  end
end
