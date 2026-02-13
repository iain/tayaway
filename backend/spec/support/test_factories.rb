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

    def session(user: nil, token: SecureRandom.hex(32), expires_at: Time.now + (30 * 24 * 60 * 60), id: SecureRandom.uuid)
      user ||= self.user
      now = Time.now
      DB[:sessions].insert(
        id: id,
        user_id: user[:id],
        token: token,
        expires_at: expires_at,
        created_at: now
      )
      DB[:sessions].where(id: id).first
    end

    class TokenResult < T::Struct
      const :token, String
    end

    class MagicTokenResult < T::Struct
      const :token, String
      const :record, MagicLinkToken
    end

    def ws_ticket(user: nil, token: SecureRandom.hex(32), expires_at: Time.now + WsTicket::EXPIRY_SECONDS, used_at: nil, id: SecureRandom.uuid)
      user ||= self.user
      now = Time.now
      DB[:ws_tickets].insert(
        id: id,
        user_id: user[:id],
        token: Auth::Token.digest(token),
        expires_at: expires_at,
        used_at: used_at,
        created_at: now
      )
      TokenResult.new(token: token)
    end

    def magic_link_token(user: nil, token: SecureRandom.hex(32), email: nil, expires_at: Time.now + (15 * 60), used_at: nil, id: SecureRandom.uuid)
      user ||= self.user
      email ||= user[:email]
      now = Time.now
      DB[:magic_link_tokens].insert(
        id: id,
        user_id: user[:id],
        token: Auth::Token.digest(token),
        email: email,
        expires_at: expires_at,
        used_at: used_at,
        created_at: now
      )
      record = MagicLinkToken.find(id)
      MagicTokenResult.new(token:, record:)
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
