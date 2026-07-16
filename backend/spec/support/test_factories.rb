# frozen_string_literal: true

require "securerandom"

module TestFactories
  class << self
    def user(email: nil, name: "Test User", id: SecureRandom.uuid)
      email ||= "user#{next_sequence(:user)}@example.com"
      now = Time.now
      DB[:users].insert(
        id: id,
        email: email,
        name: name,
        created_at: now,
        updated_at: now
      )
      DB[:users].where(id: id).first
    end

    def workspace(name: nil, id: SecureRandom.uuid)
      name ||= "Workspace #{next_sequence(:workspace)}"
      now = Time.now
      DB[:workspaces].insert(
        id: id,
        name: name,
        created_at: now,
        updated_at: now
      )
      DB[:workspaces].where(id: id).first
    end

    def workspace_membership(workspace: nil, user: nil, role: "member", id: SecureRandom.uuid)
      workspace ||= self.workspace
      user ||= self.user
      now = Time.now
      DB[:workspace_memberships].insert(
        id: id,
        workspace_id: workspace[:id],
        user_id: user[:id],
        role: role,
        created_at: now
      )
      DB[:workspace_memberships].where(id: id).first
    end

    def event(workspace: nil, user: nil, name: nil, description: "Test description", id: SecureRandom.uuid)
      workspace ||= self.workspace
      user ||= self.user
      name ||= "Event #{next_sequence(:event)}"
      now = Time.now
      DB[:events].insert(
        id: id,
        workspace_id: workspace[:id],
        user_id: user[:id],
        name: name,
        description: description,
        created_at: now,
        updated_at: now
      )
      DB[:events].where(id: id).first
    end

    def date_poll(event: nil, deadline: Time.now + (7 * 24 * 60 * 60), selected_date_range_id: nil, closed_at: nil, id: SecureRandom.uuid)
      event ||= self.event
      now = Time.now
      DB[:date_polls].insert(
        id: id,
        event_id: event[:id],
        deadline: deadline,
        selected_date_range_id: selected_date_range_id,
        closed_at: closed_at,
        created_at: now,
        updated_at: now
      )
      DB[:date_polls].where(id: id).first
    end

    def date_range(date_poll: nil, start_date: Date.today, end_date: Date.today + 7, id: SecureRandom.uuid)
      date_poll ||= self.date_poll
      now = Time.now
      DB[:date_ranges].insert(
        id: id,
        date_poll_id: date_poll[:id],
        start_date: start_date,
        end_date: end_date,
        created_at: now,
        updated_at: now
      )
      DB[:date_ranges].where(id: id).first
    end

    def vote(date_range: nil, user: nil, response: "yes", comment: nil, id: SecureRandom.uuid)
      date_range ||= self.date_range
      user ||= self.user
      now = Time.now
      DB[:votes].insert(
        id: id,
        date_range_id: date_range[:id],
        user_id: user[:id],
        response: response,
        comment: comment,
        created_at: now,
        updated_at: now
      )
      DB[:votes].where(id: id).first
    end

    def rsvp(event: nil, user: nil, attending: true, attendance: nil, start_date: nil, end_date: nil, id: SecureRandom.uuid)
      event ||= self.event
      user ||= self.user
      now = Time.now
      DB[:rsvps].insert(
        id: id,
        event_id: event[:id],
        user_id: user[:id],
        attending: attending,
        attendance: attendance && Sequel.pg_jsonb(attendance.map { |d| d.is_a?(Date) ? d.iso8601 : d }),
        start_date: start_date,
        end_date: end_date,
        created_at: now,
        updated_at: now
      )

      # Every production rsvp row has a dual-written attendance mirror
      # (doc/attendances.md phase 2), so fixtures carry one too — attendance
      # readers (chores, settlement) see the same people the rsvp describes.
      mirror_days =
        if attendance
          attendance.map { |d| entry_date(d) }
        elsif start_date && end_date
          (start_date..end_date).map(&:iso8601)
        end
      DB[:attendances]
        .insert_conflict(
          target: %i[event_id user_id],
          conflict_where: Sequel.lit("user_id IS NOT NULL"),
          update: {
            status: Sequel[:excluded][:status],
            days: Sequel[:excluded][:days],
            updated_at: Sequel[:excluded][:updated_at]
          }
        )
        .insert(
          id: SecureRandom.uuid,
          event_id: event[:id],
          user_id: user[:id],
          status: attending ? "going" : "declined",
          days: attending && mirror_days ? Sequel.pg_jsonb(mirror_days) : nil,
          created_at: now,
          updated_at: now
        )

      DB[:rsvps].where(id: id).first
    end

    def guest(workspace: nil, name: nil, placeholder: false, created_by: nil, id: SecureRandom.uuid)
      workspace ||= self.workspace
      name ||= "Guest #{next_sequence(:guest)}"
      now = Time.now
      DB[:guests].insert(
        id: id,
        workspace_id: workspace[:id],
        name: name,
        placeholder: placeholder,
        created_by_user_id: created_by&.[](:id),
        created_at: now,
        updated_at: now
      )
      DB[:guests].where(id: id).first
    end

    def attendance(event: nil, user: nil, guest: nil, host: nil, status: "going", days: nil, created_by: nil, id: SecureRandom.uuid)
      event ||= self.event
      user ||= self.user if guest.nil?
      host ||= self.user if guest
      now = Time.now
      DB[:attendances].insert(
        id: id,
        event_id: event[:id],
        user_id: user&.[](:id),
        guest_id: guest&.[](:id),
        host_user_id: host&.[](:id),
        status: status,
        days: days && Sequel.pg_jsonb(days.map { |d| d.is_a?(Date) ? d.iso8601 : d }),
        created_by_user_id: created_by&.[](:id),
        created_at: now,
        updated_at: now
      )
      DB[:attendances].where(id: id).first
    end

    def task_list(workspace: nil, user: nil, name: nil, id: SecureRandom.uuid)
      workspace ||= self.workspace
      user ||= self.user
      name ||= "Task List #{next_sequence(:task_list)}"
      now = Time.now
      DB[:task_lists].insert(
        id: id,
        workspace_id: workspace[:id],
        user_id: user[:id],
        name: name,
        created_at: now,
        updated_at: now
      )
      DB[:task_lists].where(id: id).first
    end

    def task_item(task_list: nil, user: nil, content: nil, completed_at: nil, position: nil, id: SecureRandom.uuid)
      task_list ||= self.task_list
      user ||= self.user
      content ||= "Item #{next_sequence(:task_item)}"
      position ||= (DB[:task_items].where(task_list_id: task_list[:id]).max(:position) || 0.0) + 1.0
      now = Time.now
      DB[:task_items].insert(
        id: id,
        task_list_id: task_list[:id],
        user_id: user[:id],
        content: content,
        completed_at: completed_at,
        position: position,
        created_at: now,
        updated_at: now
      )
      DB[:task_items].where(id: id).first
    end

    def chore_roster(event: nil, user: nil, id: SecureRandom.uuid)
      event ||= self.event
      user ||= self.user
      now = Time.now
      DB[:chore_rosters].insert(
        id: id,
        event_id: event[:id],
        user_id: user[:id],
        created_at: now,
        updated_at: now
      )
      DB[:chore_rosters].where(id: id).first
    end

    def chore(chore_roster: nil, name: nil, people_per_day: 1, position: nil, time: nil, id: SecureRandom.uuid)
      chore_roster ||= self.chore_roster
      name ||= "Chore #{next_sequence(:chore)}"
      position ||= (DB[:chores].where(chore_roster_id: chore_roster[:id]).max(:position) || 0.0) + 1.0
      now = Time.now
      DB[:chores].insert(
        id: id,
        chore_roster_id: chore_roster[:id],
        name: name,
        people_per_day: people_per_day,
        position: position,
        time: time,
        created_at: now,
        updated_at: now
      )
      DB[:chores].where(id: id).first
    end

    def chore_assignment(chore: nil, user: nil, attendance: nil, date: Date.today, pinned: false, note: nil, id: SecureRandom.uuid)
      chore ||= self.chore
      user ||= self.user
      now = Time.now
      DB[:chore_assignments].insert(
        id: id,
        chore_id: chore[:id],
        user_id: user[:id],
        attendance_id: attendance&.[](:id),
        date: date,
        pinned: pinned,
        note: note,
        created_at: now,
        updated_at: now
      )
      DB[:chore_assignments].where(id: id).first
    end

    def workspace_invite(workspace: nil, invited_by: nil, email: nil, name: nil, token: SecureRandom.hex(32), expires_at: Time.now + (7 * 24 * 60 * 60), accepted_at: nil, last_reminded_at: nil, id: SecureRandom.uuid)
      workspace ||= self.workspace
      invited_by ||= self.user
      email ||= "invite#{next_sequence(:workspace_invite)}@example.com"
      now = Time.now
      DB[:workspace_invites].insert(
        id: id,
        workspace_id: workspace[:id],
        invited_by: invited_by[:id],
        email: email,
        name: name,
        token: Auth::Token.digest(token),
        expires_at: expires_at,
        accepted_at: accepted_at,
        last_reminded_at: last_reminded_at,
        created_at: now,
        updated_at: now
      )
      DB[:workspace_invites].where(id: id).first
    end

    def notification(user: nil, workspace: nil, kind: "expense_added", data: { "title" => "test", "body" => "test" }, read_at: nil, id: SecureRandom.uuid)
      user ||= self.user
      now = Time.now
      DB[:notifications].insert(
        id: id,
        user_id: user[:id],
        workspace_id: workspace&.dig(:id),
        kind: kind,
        data: Sequel.pg_jsonb(data),
        read_at: read_at,
        created_at: now,
        updated_at: now
      )
      DB[:notifications].where(id: id).first
    end

    def session(user: nil, token: SecureRandom.hex(32), expires_at: Time.now + Session::EXPIRY_SECONDS, id: SecureRandom.uuid)
      user ||= self.user
      now = Time.now
      DB[:sessions].insert(
        id: id,
        user_id: user[:id],
        token: Auth::Token.digest(token),
        expires_at: expires_at,
        created_at: now
      )
      DB[:sessions].where(id: id).first.merge(token: token)
    end

    class TokenResult
      attr_reader :token

      def initialize(token:)
        @token = token
      end
    end

    class LoginTokenResult
      attr_reader :token, :record

      def initialize(token:, record:)
        @token = token
        @record = record
      end
    end

    class EmailChangeTokenResult
      attr_reader :token, :record

      def initialize(token:, record:)
        @token = token
        @record = record
      end
    end

    def ws_ticket(session: nil, user: nil, token: SecureRandom.hex(32), expires_at: Time.now + WsTicket::EXPIRY_SECONDS, used_at: nil, id: SecureRandom.uuid)
      session ||= self.session(user: user || self.user)
      now = Time.now
      DB[:ws_tickets].insert(
        id: id,
        session_id: session[:id],
        token: Auth::Token.digest(token),
        expires_at: expires_at,
        used_at: used_at,
        created_at: now
      )
      TokenResult.new(token: token)
    end

    def login_link_token(user: nil, token: SecureRandom.hex(32), email: nil, expires_at: Time.now + (15 * 60), used_at: nil, id: SecureRandom.uuid)
      user ||= self.user
      email ||= user[:email]
      now = Time.now
      DB[:login_link_tokens].insert(
        id: id,
        user_id: user[:id],
        token: Auth::Token.digest(token),
        email: email,
        expires_at: expires_at,
        used_at: used_at,
        created_at: now
      )
      record = LoginLinkToken.find(id)
      LoginTokenResult.new(token:, record:)
    end

    def email_change_token(user: nil, token: SecureRandom.hex(32), email: nil, new_email: nil, expires_at: Time.now + (15 * 60), used_at: nil, id: SecureRandom.uuid)
      user ||= self.user
      email ||= user[:email]
      new_email ||= "new#{next_sequence(:email_change)}@example.com"
      now = Time.now
      DB[:email_change_tokens].insert(
        id: id,
        user_id: user[:id],
        token: Auth::Token.digest(token),
        email: email,
        new_email: new_email,
        expires_at: expires_at,
        used_at: used_at,
        created_at: now
      )
      record = EmailChangeToken.find(id)
      EmailChangeTokenResult.new(token:, record:)
    end

    def passkey_credential(user: nil, external_id: nil, public_key: nil, sign_count: 0, aaguid: nil, name: nil, id: SecureRandom.uuid)
      user ||= self.user
      external_id ||= SecureRandom.urlsafe_base64(32)
      public_key ||= SecureRandom.urlsafe_base64(64)
      now = Time.now
      DB[:passkey_credentials].insert(
        id: id,
        user_id: user[:id],
        external_id: external_id,
        public_key: public_key,
        sign_count: sign_count,
        aaguid: aaguid,
        name: name,
        created_at: now
      )
      DB[:passkey_credentials].where(id: id).first
    end

    def audit_log_entry(workspace: nil, actor_user: nil, service: "Events::Update", outcome: "success",
                        subject_type: nil, subject_id: nil, error_code: nil, error_message: nil,
                        action_params: {}, request_id: nil, created_at: Time.now, id: SecureRandom.uuid)
      DB[:audit_log_entries].insert(
        id: id,
        actor_kind: actor_user ? "user" : "system",
        actor_user_id: actor_user&.[](:id),
        workspace_id: workspace&.[](:id),
        service: service,
        subject_type: subject_type,
        subject_id: subject_id,
        outcome: outcome,
        error_code: error_code,
        error_message: error_message,
        action_params: Sequel.pg_jsonb(action_params),
        request_id: request_id,
        created_at: created_at
      )
      DB[:audit_log_entries].where(id: id).first
    end

    def reset_sequences!
      @sequences = {}
    end

    private

    # An rsvp attendance entry is a Date, an ISO string, or a
    # `{ "date" =>, "plusOnes" => }` hash; the attendance mirror keeps only
    # the date (named guests replaced counts).
    def entry_date(entry)
      if entry.is_a?(Hash)
        (entry["date"] || entry[:date]).to_s
      elsif entry.is_a?(Date)
        entry.iso8601
      else
        entry.to_s
      end
    end

    def next_sequence(name)
      @sequences ||= {}
      @sequences[name] ||= 0
      @sequences[name] += 1
    end
  end
end
