# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Channels::InApp do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:kind_class) { Notifications::Kinds::ExpenseAdded }
  let(:data) do
    {
      actor_name: "Alice",
      description: "Pizza",
      amount: 12.5,
      event_name: "Summer Trip",
      event_url: "https://example.test/e/1"
    }
  end

  it "stores the rendered in-app payload on the row" do
    described_class.deliver(
      kind_class: kind_class,
      user_id: user[:id],
      workspace_id: workspace[:id],
      data: data
    )

    row = DB[:notifications].where(user_id: user[:id]).first
    expect(row[:kind]).to eq("expense_added")
    expect(row[:data]).to include("title", "body", "href")
  end

  it "broadcasts the new row to the recipient over the WebSocket" do
    captured = nil
    allow(Broadcaster).to receive(:object_changed) do |type, id, **kwargs|
      captured = { type: type, id: id, kwargs: kwargs }
    end

    described_class.deliver(
      kind_class: kind_class,
      user_id: user[:id],
      workspace_id: workspace[:id],
      data: data
    )

    expect(captured).not_to be_nil
    expect(captured[:type]).to eq("notification")
    expect(captured[:kwargs]).to eq(user_id: user[:id])

    # The id must reference the row that was just inserted, otherwise the
    # listener will fail to find it and downgrade the broadcast to a delete.
    inserted_id = DB[:notifications].where(user_id: user[:id]).get(:id)
    expect(captured[:id]).to eq(inserted_id)
  end
end
