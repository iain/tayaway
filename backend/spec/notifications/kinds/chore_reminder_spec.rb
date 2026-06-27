# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Kinds::ChoreReminder do
  it "is registered under its key" do
    expect(Notifications::Registry.fetch(:chore_reminder)).to eq(described_class)
  end

  it "defaults to push and in-app, the immediate channels" do
    expect(described_class.default_channels).to eq(%i[push in_app])
    expect(described_class.supported_channels).to eq(%i[push in_app])
  end

  describe ".in_app_payload" do
    let(:payload) do
      described_class.in_app_payload(
        chore_name: "Cooking",
        event_name: "Cabin trip",
        event_url: "https://tayaway.nl/events/abc/chores"
      )
    end

    it "names the chore and event in the body" do
      expect(payload[:body]).to include("Cooking")
      expect(payload[:body]).to include("Cabin trip")
    end

    it "links to the event chores page" do
      expect(payload[:href]).to eq("https://tayaway.nl/events/abc/chores")
    end

    it "has a title" do
      expect(payload[:title]).not_to be_empty
    end
  end
end
