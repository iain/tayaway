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

    it "rejects unknown kinds" do
      expect { described_class.parse("hadron:abc") }.to raise_error(ArgumentError, /unknown kind/)
    end

    it "rejects strings without an id" do
      expect { described_class.parse("workspace:") }.to raise_error(ArgumentError, /missing id/)
    end

    it "rejects non-string input" do
      expect { described_class.parse(nil) }.to raise_error(ArgumentError, /expected String/)
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

  describe "value equality" do
    it "treats two topics with the same kind and id as equal" do
      a = described_class.workspace("abc")
      b = described_class.workspace("abc")
      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it "works as a hash key" do
      h = { described_class.workspace("abc") => :marker }
      expect(h[described_class.workspace("abc")]).to eq(:marker)
    end

    it "distinguishes workspace and user topics with matching ids" do
      expect(described_class.workspace("abc")).not_to eq(described_class.user("abc"))
    end
  end
end
