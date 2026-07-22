# frozen_string_literal: true

module Workspaces
  # Creates a workspace with the caller as its owner.
  #
  # The odd one out among workspace services: there is no membership to
  # authorize against yet, so the gate is "a logged-in user asked for it"
  # rather than a WorkspacePolicy action. Everything else about a workspace
  # is policy-checked through the owner membership this service creates.
  #
  # Idempotent on the client-generated id, so a command-queue replay of a
  # create whose response never made it back collapses onto the first row
  # instead of leaving the user with two workspaces.
  module Create
    class << self
      include Workspaces::Validators

      def call(user_id:, name:, timezone: nil, id: nil)
        resolved_id = id.nil? || id.empty? ? SecureRandom.uuid : id

        Auditable.around(
          service: "Workspaces::Create",
          actor: nil,
          actor_user_id: user_id,
          subject_type: "workspace",
          subject_id: resolved_id,
          workspace_id: resolved_id,
          context: { name: name }
        ) do
          Success()
            .bind { validate_name(name) }
            .bind { |valid_name| validate_timezone(timezone).fmap { valid_name } }
            .bind { |valid_name| check_id_available(resolved_id, user_id).fmap { |replay| [valid_name, replay] } }
            .bind do |(valid_name, replay)|
              if replay
                Success({ workspace_id: resolved_id, membership_id: replay.id.to_s, created: false })
              else
                create_workspace(id: resolved_id, user_id: user_id, name: valid_name.strip, timezone: timezone)
              end
            end
        end
      end

      private

      # A row already under this id is either our own replay — same creator,
      # already the owner — or somebody else's workspace, which must not be
      # joined by guessing its id.
      def check_id_available(id, user_id)
        existing = Workspace.find(id)
        if existing.nil?
          Success(nil)
        else
          membership = WorkspaceMembership.find_by_workspace_and_user(id, user_id)
          if membership && membership.role == "owner"
            Success(membership)
          else
            Failure(ServiceError.conflict("Workspace already exists"))
          end
        end
      end

      def create_workspace(id:, user_id:, name:, timezone:)
        membership_id = SecureRandom.uuid

        DB.transaction do
          now = Time.now
          DB[:workspaces].insert(
            id: id,
            name: name,
            timezone: timezone.nil? || timezone.empty? ? Timezones::DEFAULT : timezone,
            created_at: now,
            updated_at: now
          )
          DB[:workspace_memberships].insert(
            id: membership_id,
            workspace_id: id,
            user_id: user_id,
            role: "owner",
            created_at: now
          )
        end

        # Broadcasting the membership (rather than the workspace) is what
        # gets the new workspace onto the creator's other open tabs: nobody
        # is subscribed to a workspace topic that didn't exist a moment ago,
        # and the Listener's new-member bootstrap subscribes them and ships
        # a one-shot WorkspaceSync carrying the workspace row.
        Broadcaster.object_changed("member", membership_id)

        Success({ workspace_id: id, membership_id: membership_id, created: true })
      end
    end
  end
end
