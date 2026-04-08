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
