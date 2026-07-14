# frozen_string_literal: true

module Guests
  class << self
    # Shared guard: a guest addressed through a workspace-scoped route must
    # actually belong to that workspace.
    def validate_workspace(workspace_id, guest)
      if guest.workspace_id.to_s == workspace_id.to_s
        Success(guest)
      else
        Failure(ServiceError.validation("Guest is not part of this workspace"))
      end
    end
  end
end
