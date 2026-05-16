# frozen_string_literal: true

# Serializes a WorkspaceMembership into a pool "member" object, combining
# fields from the membership and its User. Returns nil in place for any
# membership whose user row is missing (can happen during deletion races).
class MemberSerializer
  extend PoolObjectSerializer

  class << self
    # Member changes ride the workspace topic. With the auth handshake
    # auto-subscribing each connection to every workspace its user belongs
    # to, the affected user's other sessions hear about their own role
    # changes via that same topic — no user-channel duplication needed.
    # Bootstrap for "user added to a new workspace" is handled in the
    # Listener (subscribes new connections + delivers a WorkspaceSync).
    def topics_for(member)
      ["workspace:#{member.workspace_id}"]
    end

    def serialize_batch(memberships, pool:)
      return [] if memberships.empty?

      user_ids = memberships.map { |m| m.user_id.to_s }.uniq
      users_by_id = User.for_ids(user_ids).each_with_object({}) { |u, h| h[u.id.to_s] = u }

      memberships.map do |membership|
        user = users_by_id[membership.user_id.to_s]
        unless user
          APP_LOGGER.warn do
            "[MemberSerializer] Skipping membership #{membership.id} — user #{membership.user_id} " \
              "not found (deletion race or orphan row)"
          end
          next nil
        end

        build_hash(user, membership)
      end
    end

    private

    def build_hash(user, membership)
      {
        id: membership.id.to_s,
        objectType: "member",
        workspaceId: membership.workspace_id.to_s,
        userId: user.id.to_s,
        email: user.email.to_s,
        name: user.name,
        phoneNumber: user.phone_number,
        birthday: user.birthday&.iso8601,
        locationName: user.location_name,
        latitude: user.location_coordinates&.[](1),
        longitude: user.location_coordinates&.[](0),
        role: membership.role,
        createdAt: membership.created_at.iso8601(3),
        updatedAt: [user.updated_at, membership.updated_at].max.iso8601(3)
      }
    end
  end
end
