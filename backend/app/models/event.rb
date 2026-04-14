# frozen_string_literal: true

# Read-only event model.
class Event
  attr_reader :id, :workspace_id, :user_id, :name, :description, :start_date, :end_date, :location_name, :location_coordinates, :created_at, :updated_at

  def initialize(
    id:,
    workspace_id:,
    user_id:,
    name:,
    description:,
    start_date:,
    end_date:,
    location_name:,
    location_coordinates:,
    created_at:,
    updated_at:
  )
    @id = id
    @workspace_id = workspace_id
    @user_id = user_id
    @name = name
    @description = description
    @start_date = start_date
    @end_date = end_date
    @location_name = location_name
    @location_coordinates = location_coordinates
    @created_at = created_at
    @updated_at = updated_at
  end

  class << self
    include Dry::Monads[:result]
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_workspace(workspace_id)
      dataset.where(workspace_id: workspace_id).order(:created_at).all
    end

    def changed_since(workspace_id, since)
      dataset.where(workspace_id: workspace_id).where(Sequel.lit("updated_at > ?", since)).all
    end

    def for_workspace_ids(workspace_ids)
      return [] if workspace_ids.empty?

      dataset.where(workspace_id: workspace_ids).order(:created_at).limit(ValidationLimits::QUERY_LIMIT).all
    end

    def for_ids(ids)
      return [] if ids.empty?

      dataset.where(id: ids).all
    end

    private

    def dataset
      DB[:events].with_row_proc(method(:from_row))
    end

    def from_row(row)
      Event.new(
        id: UUID.new(row[:id]),
        workspace_id: UUID.new(row[:workspace_id]),
        user_id: UUID.new(row[:user_id]),
        name: row[:name],
        description: row[:description],
        start_date: row[:start_date],
        end_date: row[:end_date],
        location_name: row[:location_name],
        location_coordinates: PointParser.parse(row[:location_coordinates]),
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
