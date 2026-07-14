# frozen_string_literal: true

# The person behind an attendance row: a member (via user_id) or a guest.
# This value object and the frontend hydration composable are the only two
# places allowed to look inside the user_id XOR guest_id union — everything
# else consumes resolved attendees (doc/attendances.md, containment contract).
class Attendee < Data.define(:display_name, :user_id, :guest_id, :host_user_id)
  def guest?
    !guest_id.nil?
  end

  # Presence resolves to a billable account holder here: members bill
  # themselves, guests bill the member hosting them on this event.
  def billing_user_id
    if guest?
      host_user_id
    else
      user_id
    end
  end
end
