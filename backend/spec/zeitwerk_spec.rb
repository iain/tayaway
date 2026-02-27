# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Zeitwerk loader" do
  it "eager loads all files without errors" do
    LOADER.eager_load(force: true)
  rescue Zeitwerk::NameError => e
    raise RSpec::Expectations::ExpectationNotMetError, e.message
  end
end
