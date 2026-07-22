# frozen_string_literal: true

module Admin
  # Read models behind the admin dashboard panels. Every method returns
  # plain hashes for the ERB templates — no writes, no models, and in
  # production they run on the read-only AdminDb connection.
  module Stats
    JOB_LIST_LIMIT = 100
    # The four buckets the dashboard counts. They deliberately overlap the
    # way the counters do: a retrying job is also due or scheduled,
    # depending on where its backoff put `scheduled_at`.
    JOB_STATES = %w[due scheduled retrying dead].freeze
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    AUDIT_LIMIT = 50
    AUDIT_OUTCOMES = %w[success denied error].freeze

    class << self
      def jobs
        base = db[:async_jobs]
        now = Time.now
        {
          due: base.where(dead_at: nil).where(Sequel[:scheduled_at] <= now).count,
          scheduled: base.where(dead_at: nil).where(Sequel[:scheduled_at] > now).count,
          retrying: base.where(dead_at: nil).where { attempts > 0 }.count,
          dead: base.exclude(dead_at: nil).count
        }
      end

      # Rows behind one of the dashboard's job counters. Dead jobs read
      # newest-first (most recent failure is the interesting one); the live
      # states read by scheduled_at ascending, which is claim order.
      def job_list(state:)
        base = db[:async_jobs]
        now = Time.now
        ds =
          if state == "dead"
            base.exclude(dead_at: nil).order(Sequel.desc(:dead_at))
          elsif state == "scheduled"
            base.where(dead_at: nil).where(Sequel[:scheduled_at] > now).order(:scheduled_at)
          elsif state == "retrying"
            base.where(dead_at: nil).where { attempts > 0 }.order(:scheduled_at)
          else
            base.where(dead_at: nil).where(Sequel[:scheduled_at] <= now).order(:scheduled_at)
          end

        ds.limit(JOB_LIST_LIMIT).all
      end

      # nil for an unknown id, and for a malformed one — the id comes
      # straight off the URL, and Postgres raises on a non-uuid literal.
      def job(id)
        if id.to_s.match?(UUID)
          db[:async_jobs].where(id: id).first
        end
      end

      def users
        now = Time.now
        active_sessions = db[:sessions].where(Sequel[:expires_at] > now)
        {
          total: db[:users].count,
          new_last_7d: db[:users].where(Sequel[:created_at] > now - (7 * 86_400)).count,
          new_last_30d: db[:users].where(Sequel[:created_at] > now - (30 * 86_400)).count,
          active_sessions: active_sessions.count,
          active_users_7d: active_sessions.where(Sequel[:last_active_at] > now - (7 * 86_400))
                                          .select(:user_id).distinct.count
        }
      end

      # Histogram over active sessions — the query the protocol version gate's
      # telemetry exists for (doc/protocol-versioning.md): "can
      # MIN_SUPPORTED_VERSION be raised past N?". NULL means no request since
      # the column shipped; 0 means a client that sent no version header.
      def client_versions
        buckets = db[:sessions]
                  .where(Sequel[:expires_at] > Time.now)
                  .group(:last_seen_client_version)
                  .select {
                    [last_seen_client_version, count(Sequel.lit("*")).as(sessions), count(:user_id).distinct.as(users)]
                  }
                  .order(Sequel.desc(:last_seen_client_version, nulls: :last))
                  .all
                  .map { |row| { version: row[:last_seen_client_version], sessions: row[:sessions], users: row[:users] } }

        { min_supported: ClientProtocol::MIN_SUPPORTED_VERSION, buckets: buckets }
      end

      def audit(outcome: nil)
        ds = db[:audit_log_entries]
             .order(Sequel.desc(:created_at))
             .limit(AUDIT_LIMIT)
        ds = ds.where(outcome: outcome) if AUDIT_OUTCOMES.include?(outcome)
        entries = ds.all

        emails = actor_emails(entries)
        entries.map { |e| e.merge(actor_email: emails[e[:actor_user_id]]) }
      end

      private

      def actor_emails(entries)
        ids = entries.filter_map { |e| e[:actor_user_id] }.uniq
        if ids.empty?
          {}
        else
          db[:users].where(id: ids).select_hash(:id, :email)
        end
      end

      def db
        AdminDb.connection
      end
    end
  end
end
