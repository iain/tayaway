# frozen_string_literal: true

require "spec_helper"

RSpec.describe ObjectRegistry do
  describe "every registered entry" do
    ObjectRegistry::TYPES.each do |entry|
      context "when the entry is #{entry.key}" do
        if entry.policy
          it "has a policy class that resolves and exposes ACTIONS" do
            policy_class = Object.const_get(entry.policy)
            expect(policy_class).to respond_to(:new)
            expect(policy_class.const_get(:ACTIONS)).to be_an(Array)
          end
        else
          # Policyless entries skip the per-viewer permission attacher and
          # must therefore deliver only via the user-audience path, where
          # the recipient itself is the authorisation gate.
          it "is a user-audience entry (no policy → recipient is the audience)" do
            expect(entry.user_audience?).to be(true)
          end
        end

        it "has a serializer_class satisfying the pool-serializer contract" do
          expect(entry.serializer_class).to respond_to(:serialize_batch)
        end

        it "has a model name that resolves to a class" do
          expect { Object.const_get(entry.model) }.not_to raise_error
          expect(Object.const_get(entry.model)).to respond_to(:new)
        end

        it "is discoverable via BY_CLIENT_TYPE by its client_type" do
          expect(ObjectRegistry::BY_CLIENT_TYPE[entry.client_type]).to eq(entry)
        end

        it "declares an audience the rest of the system understands" do
          expect(entry.audience).to(eq(:workspace).or(eq(:user)))
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

    it "defaults audience to :workspace so existing entries keep their semantics" do
      entry = ObjectRegistry::Entry.new(
        key: "x", model: "Workspace", client_type: "x", tracks_user: false,
        policy: "WorkspacePolicy", serializer_class: WorkspaceSerializer
      )
      expect(entry.audience).to eq(:workspace)
      expect(entry.workspace_audience?).to be(true)
      expect(entry.user_audience?).to be(false)
    end
  end

  describe "topic derivation" do
    it "routes a member change to its workspace topic — the user is already auto-subscribed there" do
      fake_member = Struct.new(:workspace_id, :user_id).new("ws-1", "user-1")

      expect(ObjectRegistry::BY_KEY["member"].topics_for(fake_member))
        .to eq([Topic.workspace("ws-1")])
    end

    it "routes a notification to the user topic" do
      fake_notification = Struct.new(:user_id).new("user-1")

      expect(ObjectRegistry::BY_KEY["notification"].topics_for(fake_notification))
        .to eq([Topic.user("user-1")])
    end

    it "defaults to the object's workspace topic for entries without a custom topics: proc" do
      fake = Struct.new(:workspace_id).new("ws-9")

      expect(ObjectRegistry::BY_KEY["workspace_invite"].topics_for(fake))
        .to eq([Topic.workspace("ws-9")])
    end

    it "follows the join chain a chore needs to reach its workspace" do
      chore_row = TestFactories.chore
      chore = Chore.find(chore_row[:id])

      topics = ObjectRegistry::BY_KEY["chore"].topics_for(chore)

      expect(topics.size).to eq(1)
      expect(topics.first).to be_workspace
    end
  end

  # Locks in which entries opt into the optional policy_context_batch
  # prefetch. If a new serializer needs prefetched policy kwargs, add it
  # here as a load-bearing acknowledgement; if a serializer loses its
  # prefetch (or grows one accidentally), this spec catches the drift.
  describe "policy_context_batch opt-in" do
    opt_ins = %w[event date_poll date_range expense settlement settlement_transfer chore_roster attendance guest].freeze

    ObjectRegistry::TYPES.each do |entry|
      context "when the entry is #{entry.key}" do
        if opt_ins.include?(entry.key)
          it "defines policy_context_batch (PoolSerializer feeds it prefetched kwargs)" do
            expect(entry.serializer_class).to respond_to(:policy_context_batch)
          end
        else
          it "does not define policy_context_batch (PoolSerializer falls back to {})" do
            expect(entry.serializer_class).not_to respond_to(:policy_context_batch)
          end
        end
      end
    end
  end
end
