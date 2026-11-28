# frozen_string_literal: true

require "spec_helper"

# known_gap: true marks a test for a sync guarantee that doesn't hold yet
# (doc/sync/roadmap.md). This example is itself such a test: it is reported
# as pending only if the metadata is wired up, and fails the suite otherwise.
RSpec.describe "known_gap metadata" do
  it "makes an example pending with the message the coverage report reads", :known_gap do |example|
    expect(example.execution_result.pending_message).to eq("Known gap")

    raise "a known gap still fails"
  end
end
