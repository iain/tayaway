# frozen_string_literal: true

# Any workspace member may rename or delete any guest. Deletion is blocked
# while attendance rows reference the guest (attendances.guest_id is NO
# ACTION, so the DB would reject it anyway) — renaming is the remedy for a
# mislabelled guest with history. An invariant with a path forward → MODAL
# in usePermission.ts.
class GuestPolicy
  include Policy

  ACTIONS = %i[rename delete].freeze

  def initialize(_guest, has_attendances: false, **)
    @has_attendances = has_attendances
  end

  def rename
    Success()
  end

  def delete
    if @has_attendances
      Failure(:has_attendances)
    else
      Success()
    end
  end
end
