# typed: false
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

    def rsvp(event: nil, user: nil, attending: true, start_date: nil, end_date: nil, id: SecureRandom.uuid)
      event ||= self.event
      user ||= self.user
      now = Time.now
      DB[:rsvps].insert(
        id: id,
        event_id: event[:id],
        user_id: user[:id],
        attending: attending,
        start_date: start_date,
        end_date: end_date,
        created_at: now,
        updated_at: now
      )
      DB[:rsvps].where(id: id).first
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

    def task_item(task_list: nil, user: nil, content: nil, completed_at: nil, id: SecureRandom.uuid)
      task_list ||= self.task_list
      user ||= self.user
      content ||= "Item #{next_sequence(:task_item)}"
      now = Time.now
      DB[:task_items].insert(
        id: id,
        task_list_id: task_list[:id],
        user_id: user[:id],
        content: content,
        completed_at: completed_at,
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

    def chore(chore_roster: nil, name: nil, people_per_day: 1, position: nil, id: SecureRandom.uuid)
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
        created_at: now,
        updated_at: now
      )
      DB[:chores].where(id: id).first
    end

    def chore_assignment(chore: nil, user: nil, date: Date.today, pinned: false, note: nil, id: SecureRandom.uuid)
      chore ||= self.chore
      user ||= self.user
      now = Time.now
      DB[:chore_assignments].insert(
        id: id,
        chore_id: chore[:id],
        user_id: user[:id],
        date: date,
        pinned: pinned,
        note: note,
        created_at: now,
        updated_at: now
      )
      DB[:chore_assignments].where(id: id).first
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

    class TokenResult < T::Struct
      const :token, String
    end

    class LoginTokenResult < T::Struct
      const :token, String
      const :record, LoginLinkToken
    end

    class EmailChangeTokenResult < T::Struct
      const :token, String
      const :record, EmailChangeToken
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

    def reset_sequences!
      @sequences = {}
    end

    private

    def next_sequence(name)
      @sequences ||= {}
      @sequences[name] ||= 0
      @sequences[name] += 1
    end
  end
end
