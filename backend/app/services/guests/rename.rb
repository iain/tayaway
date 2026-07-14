# frozen_string_literal: true

module Guests
  # Rename a guest. Renaming also clears the placeholder flag: a
  # backfill-synthesized "Guest 1 (host)" becomes a real, picker-visible
  # person the moment somebody gives them a name.
  module Rename
    class << self
      include LengthValidation

      def call(workspace_id:, membership:, guest_id:, name:)
        Auditable.around(
          service: "Guests::Rename",
          actor: membership,
          subject_type: "guest",
          subject_id: guest_id,
          context: {}
        ) do
          Success()
            .bind { Guest.find_result(guest_id) }
            .bind { |guest| Guests.validate_workspace(workspace_id, guest) }
            .bind { |guest| GuestPolicy.enforce(:rename, guest, membership: membership) }
            .bind { |guest| validate_length(name, max: ValidationLimits::SHORT_STRING, field: "Name", required: true).bind { Success(guest) } }
            .bind { |guest| rename(guest, name.strip) }
        end
      end

      private

      def rename(guest, name)
        DB.transaction do
          DB[:guests].where(id: guest.id).update(name: name, placeholder: false, updated_at: Time.now)
          Broadcaster.object_changed("guest", guest.id)
        end

        Success({ guest_id: guest.id.to_s })
      end
    end
  end
end
