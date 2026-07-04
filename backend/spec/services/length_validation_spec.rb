# frozen_string_literal: true

require "spec_helper"

RSpec.describe LengthValidation do
  subject(:validator) { Class.new { include LengthValidation }.new }

  describe "#validate_length" do
    it "passes a value within the limit" do
      result = validator.validate_length("hello", max: 10, field: "Name")

      expect(result.success?).to be true
      expect(result.value!).to eq("hello")
    end

    it "fails a value over the limit with a field-named message" do
      result = validator.validate_length("a" * 11, max: 10, field: "Name")

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Name is too long (maximum 10 characters)")
      expect(result.failure.http_status).to eq(400)
    end

    it "counts the boundary length as valid" do
      result = validator.validate_length("a" * 10, max: 10, field: "Name")

      expect(result.success?).to be true
    end

    context "when required" do
      it "fails on nil" do
        result = validator.validate_length(nil, max: 10, field: "Name", required: true)

        expect(result.failure?).to be true
        expect(result.failure.message).to eq("Name is required")
        expect(result.failure.http_status).to eq(400)
      end

      it "fails on a whitespace-only value" do
        result = validator.validate_length("   ", max: 10, field: "Name", required: true)

        expect(result.failure?).to be true
        expect(result.failure.message).to eq("Name is required")
      end
    end

    context "when optional (the default)" do
      it "passes nil through unchanged" do
        result = validator.validate_length(nil, max: 10, field: "Note")

        expect(result.success?).to be true
        expect(result.value!).to be_nil
      end

      it "passes a blank string through (clears the field)" do
        result = validator.validate_length("", max: 10, field: "Note")

        expect(result.success?).to be true
        expect(result.value!).to eq("")
      end
    end
  end
end
