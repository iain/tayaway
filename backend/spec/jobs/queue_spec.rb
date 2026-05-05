# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jobs::Queue do
  describe ".enqueue" do
    it "runs the job inline in the test environment" do
      stub_const("APP_ENV", "test")
      called_with = nil
      stub_const("Jobs::FakeNoop", Class.new(Jobs::Base) do
        define_method(:initialize) { |label:| @label = label }
        define_method(:call) { called_with = @label }
      end)

      described_class.enqueue(job_class: "Jobs::FakeNoop", args: { label: "ran" })

      expect(called_with).to eq("ran")
    end

    it "stringifies keyword keys before passing them through inline" do
      stub_const("APP_ENV", "test")
      stub_const("Jobs::FakeKeyCheck", Class.new(Jobs::Base) do
        define_method(:initialize) { |label:| @label = label }
        define_method(:call) { @label }
      end)

      expect do
        described_class.enqueue(job_class: "Jobs::FakeKeyCheck", args: { label: "ok" })
      end.not_to raise_error
    end
  end
end
