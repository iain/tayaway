# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jobs::Base do
  describe ".perform_later" do
    it "delegates to Jobs::Queue with the class name and args" do
      allow(Jobs::Queue).to receive(:enqueue)
      stub_const("Jobs::FakeJob", Class.new(described_class) do
        define_method(:call) { |x:| x }
      end
      )

      Jobs::FakeJob.perform_later(x: 1)

      expect(Jobs::Queue).to have_received(:enqueue).with(job_class: "Jobs::FakeJob", args: { x: 1 })
    end
  end

  describe ".run" do
    it "calls the subclass's `call` with symbolised kwargs from the JSONB payload" do
      stub_const("Jobs::FakeRun", Class.new(described_class) do
        define_method(:call) { |x:, y:| x + y }
      end
      )

      expect(Jobs::FakeRun.run({ "x" => 2, "y" => 3 })).to eq(5)
    end
  end
end
