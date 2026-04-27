# frozen_string_literal: true

# Shared subject-membership guard for services that act on behalf of a user.
#
# Many services accept a `user_id` (the subject — the user the action is
# *about*, distinct from the actor performing it). Before mutating that
# user's data, we check the subject actually belongs to the workspace.
# Centralised here so the rule cannot drift between domains.
module Subjects
  class << self
    # @return [Success(event), Failure(ServiceError)]
    def validate(event:, user_id:)
      if WorkspaceMembership.find_by_workspace_and_user(event.workspace_id, user_id)
        Success(event)
      else
        Failure(ServiceError.validation("User is not a member of this workspace"))
      end
    end
  end
end
