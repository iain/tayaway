# frozen_string_literal: true

module Guests
  # Delete a guest. Allowed only while no attendance rows reference them
  # (the guest_id FK is NO ACTION, so the DB backstops this) — otherwise
  # rename is the remedy. Attendance history therefore never loses its
  # people.
  module Delete
    class << self
      def call(workspace_id:, membership:, guest_id:)
        Auditable.around(
          service: "Guests::Delete",
          actor: membership,
          subject_type: "guest",
          subject_id: guest_id,
          context: {}
        ) do
          Success()
            .bind { Guest.find_result(guest_id) }
            .bind { |guest| Guests.validate_workspace(workspace_id, guest) }
            .bind { |guest|
              GuestPolicy.enforce(
                :delete, guest,
                membership: membership,
                has_attendances: DB[:attendances].where(guest_id: guest.id).count > 0
              )
            }
            .bind { |guest| delete_guest(guest) }
        end
      end

      private

      def delete_guest(guest)
        DB.transaction do
          DB[:deleted_items].insert(
            workspace_id: guest.workspace_id,
            object_type: "guest",
            object_id: guest.id
          )
          DB[:guests].where(id: guest.id).delete
          Broadcaster.object_deleted("guest", guest.id, topics: [Topic.workspace(guest.workspace_id)])
        end

        Success({ deleted: [{ objectType: "guest", id: guest.id.to_s }] })
      end
    end
  end
end
