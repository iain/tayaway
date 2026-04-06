# frozen_string_literal: true

# Read-only Settlement model.
class Settlement
  attr_reader :id, :event_id, :user_id, :created_at, :updated_at

  def initialize(
    id:,
    event_id:,
    user_id:,
    created_at:,
    updated_at:
  )
    @id = id
    @event_id = event_id
    @user_id = user_id
    @created_at = created_at
    @updated_at = updated_at
  end

  def to_api_hash(transfer_ids:)
    {
      id: id.to_s,
      objectType: "settlement",
      eventId: event_id.to_s,
      userId: user_id&.to_s,
      transferIds: transfer_ids,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    include Result::Methods
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_event(event_id)
      dataset.where(event_id: event_id).order(:created_at).all
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:events, id: :event_id)
        .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
        .where(Sequel.lit("settlements.updated_at > ?", since))
        .select_all(:settlements)
        .all
    end

    private

    def dataset
      DB[:settlements].with_row_proc(method(:from_row))
    end

    def from_row(row)
      Settlement.new(
        id: UUID.new(row[:id]),
        event_id: UUID.new(row[:event_id]),
        user_id: row[:user_id] ? UUID.new(row[:user_id]) : nil,
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
