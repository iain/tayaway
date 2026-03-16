# typed: false
# frozen_string_literal: true

class App
  # Unauthenticated invite endpoints
  hash_path "/api/invites/accept" do |r|
    # POST /api/invites/accept - Accept an invitation
    r.post do
      result = Invites::Accept.call(token_jwt: r.params["token"])
      handle_result(result)
    end
  end

  hash_path "/api/invites/info" do |r|
    # GET /api/invites/info?token=JWT - Get invite info (workspace name, email)
    r.get do
      token_jwt = r.params["token"]

      unless token_jwt && !token_jwt.empty?
        response.status = 400
        next { error: "Token is required" }
      end

      begin
        decoded = Auth::Token.decode_invite(token_jwt)
      rescue JWT::ExpiredSignature
        response.status = 410
        next { error: "This invitation has expired" }
      rescue JWT::DecodeError
        response.status = 400
        next { error: "Invalid invitation link" }
      end

      token_hash = Auth::Token.digest(decoded[:token])
      invite = WorkspaceInvite.find_valid(token_hash, decoded[:email])

      unless invite
        response.status = 410
        next { error: "This invitation is no longer valid" }
      end

      workspace = Workspace.find(invite.workspace_id)

      {
        workspaceName: workspace&.name || "Unknown workspace",
        email: invite.email.to_s
      }
    end
  end

  # Authenticated invite endpoints
  hash_branch("api", "invites") do |r|
    require_auth

    r.is do
      # GET /api/invites?workspace_id=X - List pending invites
      r.get do
        workspace_id = r.params["workspace_id"]

        unless workspace_id && member_of_workspace?(workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        invites = WorkspaceInvite.all_non_accepted_for_workspace(workspace_id)
        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_all(invites, type: :workspace_invite)
        { objects: pool.to_a }
      end

      # POST /api/invites - Create an invitation (admin/owner only)
      r.post do
        workspace_id = r.params["workspace_id"]

        unless workspace_id && member_of_workspace?(workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        require_admin_or_owner!(workspace_id)

        result = Invites::Create.call(
          email: r.params["email"]&.strip&.downcase,
          workspace_id: workspace_id,
          invited_by: current_user.id,
          name: r.params["name"]
        )
        handle_result(result, success_status: 201)
      end
    end

    r.on String do |id|
      # DELETE /api/invites/:id - Cancel an invitation (admin/owner only)
      r.delete do
        workspace_id = r.params["workspace_id"]

        unless workspace_id && member_of_workspace?(workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        require_admin_or_owner!(workspace_id)

        result = Invites::Cancel.call(invite_id: id, workspace_id: workspace_id)
        handle_result(result)
      end

      # POST /api/invites/:id/remind - Resend invitation email (admin/owner only)
      r.on "remind" do
        r.post do
          workspace_id = r.params["workspace_id"]

          unless workspace_id && member_of_workspace?(workspace_id)
            response.status = 403
            next { error: "Access denied" }
          end

          require_admin_or_owner!(workspace_id)

          result = Invites::Remind.call(invite_id: id, workspace_id: workspace_id)
          handle_result(result)
        end
      end
    end
  end
end
