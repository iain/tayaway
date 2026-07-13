# frozen_string_literal: true

module AuditLogs
  # Owner-only read of a workspace's audit trail, newest first, keyset
  # paginated. Deliberately not pool-shaped: audit rows are far too numerous
  # to sync, so the page fetches them over plain HTTP instead.
  module ListForWorkspace
    PAGE_SIZE = 100

    class << self
      def call(workspace_id:, membership:, cursor: nil, limit: PAGE_SIZE)
        Success()
          .bind { Workspace.find_result(workspace_id) }
          .bind { |workspace| WorkspacePolicy.enforce(:view_audit_log, workspace, membership: membership) }
          .bind { |workspace| parse_cursor(cursor).fmap { |before| [workspace, before] } }
          .bind { |(workspace, before)| Success(page(workspace, before, limit.clamp(1, PAGE_SIZE))) }
      end

      private

      # Cursors are "<created_at iso8601, microsecond precision>|<entry id>" —
      # enough to resume strictly after the last row of the previous page even
      # when several rows share a timestamp.
      def parse_cursor(cursor)
        if cursor.nil?
          Success(nil)
        else
          timestamp, id = cursor.split("|", 2)
          Success([Time.iso8601(timestamp.to_s), UUID.new(id.to_s)])
        end
      rescue ArgumentError, UUID::Invalid
        Failure(ServiceError.validation("Invalid cursor"))
      end

      def page(workspace, before, limit)
        entries = AuditLogEntry.page_for_workspace(
          workspace.id,
          before_created_at: before&.[](0),
          before_id: before&.[](1)&.to_s,
          limit: limit + 1
        )
        has_more = entries.length > limit
        entries = entries.first(limit)

        {
          entries: serialize(entries),
          nextCursor: has_more ? cursor_for(entries.last) : nil
        }
      end

      def cursor_for(entry)
        "#{entry.created_at.utc.iso8601(6)}|#{entry.id}"
      end

      def serialize(entries)
        names = actor_names(entries)
        entries.map do |entry|
          {
            id: entry.id.to_s,
            createdAt: entry.created_at.iso8601(3),
            actorKind: entry.actor_kind,
            actorUserId: entry.actor_user_id&.to_s,
            actorName: names[entry.actor_user_id&.to_s],
            service: entry.service,
            subjectType: entry.subject_type,
            subjectId: entry.subject_id&.to_s,
            outcome: entry.outcome,
            errorCode: entry.error_code,
            errorMessage: entry.error_message,
            actionParams: entry.action_params,
            requestId: entry.request_id,
            idempotencyKeyHash: entry.idempotency_key_hash
          }
        end
      end

      # Resolved live rather than denormalised onto the audit rows, which
      # stay free of personal data by design (see Auditable). Names of
      # since-deleted users simply come back nil.
      def actor_names(entries)
        ids = entries.filter_map { |entry| entry.actor_user_id&.to_s }.uniq
        User.for_ids(ids).to_h { |user| [user.id.to_s, user.name] }
      end
    end
  end
end
