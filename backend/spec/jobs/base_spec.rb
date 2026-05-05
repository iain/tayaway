# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jobs::Base do
  describe ".perform_later" do
    it "delegates to Jobs::Queue with the class name and args" do
      stub_const("APP_ENV", "test")
      allow(Jobs::Queue).to receive(:enqueue)
      stub_const("Jobs::FakeJob", Class.new(described_class) do
        define_method(:initialize) { |x:| @x = x }
        define_method(:call) { @x }
      end
      )

      Jobs::FakeJob.perform_later(x: 1)

      expect(Jobs::Queue).to have_received(:enqueue).with(job_class: "Jobs::FakeJob", args: { x: 1 })
    end
  end

  describe ".run" do
    it "instantiates the subclass with symbolised kwargs and invokes call" do
      stub_const("Jobs::FakeRun", Class.new(described_class) do
        define_method(:initialize) { |x:, y:| @x, @y = x, y }
        define_method(:call) { @x + @y }
      end
      )

      expect(Jobs::FakeRun.run({ "x" => 2, "y" => 3 })).to eq(5)
    end
  end
end
