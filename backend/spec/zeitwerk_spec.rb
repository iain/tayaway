# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Zeitwerk loader" do
  it "eager loads all files without errors" do
    expect { LOADER.eager_load(force: true) }.not_to raise_error
  end
end
