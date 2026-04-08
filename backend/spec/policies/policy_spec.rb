# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Policy module" do
  let(:test_policy_class) do
    Class.new do
      include Policy

      const_set(:ACTIONS, %i[edit delete].freeze)

      def initialize(allowed_edit:, allowed_delete:)
        @allowed_edit = allowed_edit
        @allowed_delete = allowed_delete
      end

      def edit
        if @allowed_edit
          Success()
        else
          Failure(:not_owner)
        end
      end

      def delete
        if @allowed_delete
          Success()
        else
          Failure(:has_settlements)
        end
      end
    end
  end

  describe ".enforce" do
    let(:subject_object) { Object.new }

    let(:enforce_policy_class) do
      Class.new do
        include Policy

        const_set(:ACTIONS, %i[edit delete].freeze)

        def initialize(_subject, allowed:, **)
          @allowed = allowed
        end

        def edit
          @allowed ? Success() : Failure(:not_owner)
        end

        def delete
          @allowed ? Success() : Failure(:has_settlements)
        end
      end
    end

    it "returns Success with the subject when allowed" do
      result = enforce_policy_class.enforce(:edit, subject_object, allowed: true)

      expect(result).to be_success
      expect(result.value!).to equal(subject_object)
    end

    it "returns Failure with ServiceError when denied" do
      result = enforce_policy_class.enforce(:edit, subject_object, allowed: false)

      expect(result).to be_failure
      expect(result.failure).to be_a(ServiceError)
      expect(result.failure.http_status).to eq(403)
      expect(result.failure.message).to include("not_owner")
    end

    it "raises ArgumentError for unknown actions" do
      expect {
        enforce_policy_class.enforce(:fly, subject_object, allowed: true)
      }.to raise_error(ArgumentError, /Unknown action :fly/)
    end
  end

  describe "#permissions" do
    it "returns allowed: true for successful actions" do
      policy = test_policy_class.new(allowed_edit: true, allowed_delete: true)

      expect(policy.permissions).to eq(
        edit: { allowed: true },
        delete: { allowed: true }
      )
    end

    it "returns allowed: false with reason for failed actions" do
      policy = test_policy_class.new(allowed_edit: false, allowed_delete: false)

      expect(policy.permissions).to eq(
        edit: { allowed: false, reason: "not_owner" },
        delete: { allowed: false, reason: "has_settlements" }
      )
    end

    it "handles mixed results" do
      policy = test_policy_class.new(allowed_edit: true, allowed_delete: false)

      expect(policy.permissions).to eq(
        edit: { allowed: true },
        delete: { allowed: false, reason: "has_settlements" }
      )
    end
  end
end
