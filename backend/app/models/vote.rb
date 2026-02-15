# typed: true
# frozen_string_literal: true

# Read-only vote model.
class Vote < T::Struct
  extend T::Sig

  const :id, UUID
  const :date_range_id, UUID
  const :user_id, UUID
  const :response, VoteResponse
  const :comment, T.nilable(String)
  const :created_at, Time
  const :updated_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      objectType: "vote",
      dateRangeId: date_range_id.to_s,
      userId: user_id.to_s,
      response: response.serialize,
      comment: comment,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig

    sig { params(id: T.any(String, UUID)).returns(T.nilable(Vote)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(date_range_id: T.any(String, UUID)).returns(T::Array[Vote]) }
    def for_date_range(date_range_id)
      dataset.where(date_range_id: date_range_id).all
    end

    sig { params(date_range_id: T.any(String, UUID)).returns(T::Array[String]) }
    def ids_for_date_range(date_range_id)
      DB[:votes].where(date_range_id: date_range_id).select_map(:id)
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[Vote]) }
    def updated_since_for_workspace(workspace_id, since)
      dataset
        .join(:date_ranges, id: :date_range_id)
        .join(:date_polls, id: Sequel[:date_ranges][:date_poll_id])
        .join(:events, id: Sequel[:date_polls][:event_id])
        .where(Sequel[:events][:workspace_id] => workspace_id)
        .where(Sequel.lit("votes.updated_at > ?", since))
        .select_all(:votes)
        .all
    end

    sig { params(date_range_ids: T::Array[String]).returns(T::Array[Vote]) }
    def for_date_range_ids(date_range_ids)
      return [] if date_range_ids.empty?

      dataset.where(date_range_id: date_range_ids).all
    end

    sig { params(date_range_id: T.any(String, UUID), user_id: T.any(String, UUID)).returns(T.nilable(Vote)) }
    def find_by_date_range_and_user(date_range_id, user_id)
      dataset.where(date_range_id: date_range_id, user_id: user_id).first
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:votes].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(Vote) }
    def from_row(row)
      Vote.new(
        id: UUID.new(row[:id]),
        date_range_id: UUID.new(row[:date_range_id]),
        user_id: UUID.new(row[:user_id]),
        response: VoteResponse.deserialize(row[:response]),
        comment: row[:comment],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
