# frozen_string_literal: true

require "spec_helper"

RSpec.describe ObjectRegistry do
  describe "every registered entry" do
    ObjectRegistry::TYPES.each do |entry|
      context "when the entry is #{entry.key}" do
        it "has a policy class that resolves and exposes ACTIONS" do
          policy_class = Object.const_get(entry.policy)
          expect(policy_class).to respond_to(:new)
          expect(policy_class.const_get(:ACTIONS)).to be_an(Array)
        end

        it "has a serializer_class satisfying the pool-serializer contract" do
          expect(entry.serializer_class).to respond_to(:serialize_batch)
          expect(entry.serializer_class).to respond_to(:policy_context)
          expect(entry.serializer_class).to respond_to(:policy_context_batch)
        end

        it "has a model name that resolves to a class" do
          expect { Object.const_get(entry.model) }.not_to raise_error
          expect(Object.const_get(entry.model)).to respond_to(:new)
        end

        it "is discoverable via BY_CLIENT_TYPE by its client_type" do
          expect(ObjectRegistry::BY_CLIENT_TYPE[entry.client_type]).to eq(entry)
        end
      end
    end
  end

  describe "::Entry" do
    it "requires serializer_class and policy when constructing a new entry" do
      expect do
        ObjectRegistry::Entry.new(
          key: "x", model: "X", client_type: "x", tracks_user: false
        )
      end.to raise_error(ArgumentError, /missing keyword/)
    end
  end
end
