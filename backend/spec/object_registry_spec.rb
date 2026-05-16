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

  describe "broadcast_audiences delegation to serializer" do
    it "fans out a member change to both workspace and user audiences" do
      fake_member = Struct.new(:workspace_id, :user_id).new("ws-1", "user-1")

      audiences = MemberSerializer.broadcast_audiences_for(fake_member)

      expect(audiences).to contain_exactly(
        { kind: "workspace", id: "ws-1" },
        { kind: "user", id: "user-1" }
      )
    end

    it "routes a notification to the user audience only" do
      fake_notification = Struct.new(:user_id).new("user-1")

      audiences = NotificationSerializer.broadcast_audiences_for(fake_notification)

      expect(audiences).to eq([{ kind: "user", id: "user-1" }])
    end
  end
end
