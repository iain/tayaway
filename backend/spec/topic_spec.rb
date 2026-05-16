# frozen_string_literal: true

require "spec_helper"

RSpec.describe Topic do
  describe "construction" do
    it "builds a workspace topic from any id-shaped value" do
      topic = described_class.workspace("ws-1")
      expect(topic.kind).to eq(:workspace)
      expect(topic.id).to eq("ws-1")
      expect(topic).to be_workspace
      expect(topic).not_to be_user
    end

    it "builds a user topic" do
      topic = described_class.user("user-1")
      expect(topic.kind).to eq(:user)
      expect(topic).to be_user
    end

    it "coerces non-string ids to string" do
      uuid = SecureRandom.uuid
      expect(described_class.workspace(uuid).id).to eq(uuid.to_s)
    end
  end

  describe ".parse" do
    it "round-trips a workspace topic" do
      expect(described_class.parse("workspace:abc")).to eq(described_class.workspace("abc"))
    end

    it "round-trips a user topic" do
      expect(described_class.parse("user:xyz")).to eq(described_class.user("xyz"))
    end

    [
      ["unknown kind", "hadron:abc", /unknown kind/],
      ["missing id", "workspace:", /missing id/],
      ["non-string input", nil, /expected String/]
    ].each do |desc, input, message|
      it "rejects #{desc}" do
        expect { described_class.parse(input) }.to raise_error(ArgumentError, message)
      end
    end
  end

  describe "wire format" do
    it "stringifies to kind:id" do
      expect(described_class.workspace("abc").to_s).to eq("workspace:abc")
      expect(described_class.user("xyz").to_s).to eq("user:xyz")
    end

    it "JSON-serializes as the wire string, not as an object" do
      payload = { topics: [described_class.workspace("abc"), described_class.user("xyz")] }
      expect(JSON.parse(payload.to_json)).to eq("topics" => ["workspace:abc", "user:xyz"])
    end
  end

  # Topic gets value equality from Data.define; we only assert that
  # different-kind, same-id topics stay distinct — the bit our consumers
  # actually rely on for hash/Set partitioning.
  it "distinguishes workspace and user topics with matching ids" do
    expect(described_class.workspace("abc")).not_to eq(described_class.user("abc"))
  end
end
