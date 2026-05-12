# frozen_string_literal: true

# Rich development seed: a workspace with several members, multiple events
# at different lifecycle stages (open poll, closed poll + RSVPs, planned with
# chores and settled expenses), task lists, and a pending invite. Idempotent —
# rerun to refresh state without duplicating rows.

require_relative "../config/environment"
require "digest"

raise "Refusing to run seed_dev outside development" unless APP_CONFIG.development?

# Deterministic UUIDs so reruns upsert the same rows.
def det_uuid(label)
  hex = Digest::SHA1.hexdigest("tayaway-seed-dev:#{label}")
  "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
end

now = Time.now
today = Date.today

users = {
  test: { email: "test@example.com", name: "Test User", role: "owner" },
  alice: { email: "alice@example.com", name: "Alice Andersson", role: "admin" },
  bob: { email: "bob@example.com", name: "Bob Bakker", role: "member" },
  charlie: { email: "charlie@example.com", name: "Charlie Chen", role: "member" },
  diana: { email: "diana@example.com", name: "Diana Diaz", role: "member" }
}

workspace_id = det_uuid("workspace:main")

DB.transaction do
  # ── Users ─────────────────────────────────────────────────────────────────
  users.each do |key, attrs|
    DB[:users].insert_conflict(
      target: :email,
      update: { name: attrs[:name], updated_at: now }
    ).insert(
      id: det_uuid("user:#{key}"),
      email: attrs[:email],
      name: attrs[:name],
      created_at: now,
      updated_at: now
    )
  end
  user_id = users.transform_values { |a| DB[:users].where(email: a[:email]).get(:id) }
  user_id_for = ->(key) { user_id.fetch(key) }

  # IBANs so the QR / copy-IBAN flow on settlements has something to show.
  # Public example IBANs (Wikipedia / ECB documentation); not real accounts.
  ibans = {
    test: "NL18RABO0123459876",
    alice: "NL91ABNA0417164300",
    bob: "BE71096123456769",
    charlie: "DE89370400440532013000",
    diana: "FR1420041010050500013M02606"
  }
  ibans.each do |key, iban|
    uid = user_id_for[key]
    DB[:users].where(id: uid).update(iban: Encryption.encrypt(iban, user_id: uid), updated_at: now)
  end

  # ── Workspace + memberships ───────────────────────────────────────────────
  DB[:workspaces].insert_conflict(
    target: :id,
    update: { name: "Friends & Family", updated_at: now }
  ).insert(id: workspace_id, name: "Friends & Family", created_at: now, updated_at: now)

  users.each_key do |key|
    DB[:workspace_memberships].insert_conflict(
      target: %i[workspace_id user_id],
      update: { role: users[key][:role] }
    ).insert(
      id: det_uuid("membership:#{key}"),
      workspace_id: workspace_id,
      user_id: user_id_for[key],
      role: users[key][:role],
      created_at: now
    )
  end

  # A pending invite so the invite UI has something to show.
  DB[:workspace_invites].insert_conflict(
    target: :id,
    update: { last_reminded_at: now - (60 * 60 * 24) }
  ).insert(
    id: det_uuid("invite:eve"),
    workspace_id: workspace_id,
    invited_by: user_id_for[:test],
    email: "eve@example.com",
    name: "Eve Edwards",
    token: Digest::SHA256.hexdigest("seed-invite-token-eve"),
    expires_at: now + (60 * 60 * 24 * 14),
    last_reminded_at: nil,
    created_at: now - (60 * 60 * 24 * 2),
    updated_at: now - (60 * 60 * 24 * 2)
  )

  # ── Helper: build an event with a date poll ───────────────────────────────
  build_event = lambda do |key, name:, description:, owner:, start_date: nil, end_date: nil, location: nil|
    event_id = det_uuid("event:#{key}")
    DB[:events].insert_conflict(
      target: :id,
      update: { name: name, description: description, updated_at: now,
                start_date: start_date, end_date: end_date,
                location_name: location }
    ).insert(
      id: event_id,
      workspace_id: workspace_id,
      user_id: user_id_for[owner],
      name: name,
      description: description,
      start_date: start_date,
      end_date: end_date,
      location_name: location,
      created_at: now,
      updated_at: now
    )
    event_id
  end

  # ── Event 1: cabin trip — fully planned, settled, with chores ────────────
  cabin_start = today + 14
  cabin_end = today + 17
  cabin_id = build_event.call(
    :cabin,
    name: "Cabin trip in the Ardennes",
    description: "Long weekend at the cabin. Bring warm clothes and board games.",
    owner: :test,
    start_date: cabin_start,
    end_date: cabin_end,
    location: "La Roche-en-Ardenne, Belgium"
  )

  # Closed date poll, with one of the ranges marked as the winner.
  cabin_poll_id = det_uuid("poll:cabin")
  cabin_winning_range_id = det_uuid("daterange:cabin:winner")
  cabin_alt_range_id = det_uuid("daterange:cabin:alt")
  DB[:date_polls].insert_conflict(
    target: :id,
    update: { closed_at: now - (60 * 60 * 24 * 3), selected_date_range_id: cabin_winning_range_id,
              updated_at: now }
  ).insert(
    id: cabin_poll_id,
    event_id: cabin_id,
    deadline: now - (60 * 60 * 24 * 3),
    closed_at: now - (60 * 60 * 24 * 3),
    selected_date_range_id: nil, # set after ranges exist
    created_at: now - (60 * 60 * 24 * 10),
    updated_at: now
  )

  [
    { id: cabin_winning_range_id, start: cabin_start, finish: cabin_end },
    { id: cabin_alt_range_id, start: cabin_start + 7, finish: cabin_end + 7 }
  ].each do |r|
    DB[:date_ranges].insert_conflict(
      target: :id,
      update: { start_date: r[:start], end_date: r[:finish], updated_at: now }
    ).insert(
      id: r[:id], date_poll_id: cabin_poll_id,
      start_date: r[:start], end_date: r[:finish],
      created_at: now - (60 * 60 * 24 * 10), updated_at: now
    )
  end
  DB[:date_polls].where(id: cabin_poll_id)
                 .update(selected_date_range_id: cabin_winning_range_id, updated_at: now)

  # Votes: most prefer the winner, one prefers the alt, one votes "no".
  vote_plan = [
    { user: :test, range: cabin_winning_range_id, response: "yes" },
    { user: :alice, range: cabin_winning_range_id, response: "yes", comment: "In!" },
    { user: :bob, range: cabin_winning_range_id, response: "preferably_not" },
    { user: :charlie, range: cabin_winning_range_id, response: "yes" },
    { user: :diana, range: cabin_winning_range_id, response: "no", comment: "Out of town." },
    { user: :alice, range: cabin_alt_range_id, response: "yes" },
    { user: :bob, range: cabin_alt_range_id, response: "yes" },
    { user: :diana, range: cabin_alt_range_id, response: "yes" }
  ]
  vote_plan.each do |v|
    DB[:votes].insert_conflict(
      target: %i[date_range_id user_id],
      update: { response: v[:response], comment: v[:comment], updated_at: now }
    ).insert(
      id: det_uuid("vote:cabin:#{v[:user]}:#{v[:range]}"),
      date_range_id: v[:range],
      user_id: user_id_for[v[:user]],
      response: v[:response],
      comment: v[:comment],
      created_at: now - (60 * 60 * 24 * 9),
      updated_at: now
    )
  end

  # RSVPs: four attending (one with custom dates), one declines.
  # Diana never replied — test marked her as not attending so the headcount
  # reflects reality. That row demonstrates the on-behalf-of capability:
  # the subject is :diana but the filer (created_by) is :test.
  rsvp_plan = [
    { user: :test, attending: true },
    { user: :alice, attending: true },
    { user: :bob, attending: true, start: cabin_start + 1, finish: cabin_end },
    { user: :charlie, attending: true },
    { user: :diana, attending: false, filed_by: :test }
  ]
  rsvp_plan.each do |r|
    DB[:rsvps].insert_conflict(
      target: %i[event_id user_id],
      update: { attending: r[:attending], start_date: r[:start], end_date: r[:finish],
                created_by_user_id: Sequel[:excluded][:created_by_user_id],
                updated_at: now }
    ).insert(
      id: det_uuid("rsvp:cabin:#{r[:user]}"),
      event_id: cabin_id,
      user_id: user_id_for[r[:user]],
      created_by_user_id: user_id_for[r[:filed_by] || r[:user]],
      attending: r[:attending],
      start_date: r[:start],
      end_date: r[:finish],
      created_at: now - (60 * 60 * 24 * 7),
      updated_at: now
    )
  end

  # Task lists for the cabin trip.
  cabin_tl_packing = det_uuid("tasklist:cabin:packing")
  cabin_tl_groceries = det_uuid("tasklist:cabin:groceries")
  [
    { id: cabin_tl_packing, name: "Packing", position: 1.0, owner: :test },
    { id: cabin_tl_groceries, name: "Groceries", position: 2.0, owner: :alice }
  ].each do |list|
    DB[:task_lists].insert_conflict(
      target: :id,
      update: { name: list[:name], position: list[:position], updated_at: now }
    ).insert(
      id: list[:id], workspace_id: workspace_id, user_id: user_id_for[list[:owner]],
      name: list[:name], position: list[:position],
      created_at: now, updated_at: now
    )
  end

  packing_items = [
    ["Sleeping bags", :test, true],
    ["Board games", :charlie, true],
    ["Bluetooth speaker", :bob, false],
    ["Hiking boots", :alice, false]
  ]
  packing_items.each_with_index do |(content, owner, done), i|
    DB[:task_items].insert_conflict(
      target: :id,
      update: { content: content, completed_at: done ? now - (60 * 60 * 5) : nil,
                updated_at: now }
    ).insert(
      id: det_uuid("task:cabin:packing:#{i}"),
      task_list_id: cabin_tl_packing,
      user_id: user_id_for[owner],
      content: content,
      completed_at: done ? now - (60 * 60 * 5) : nil,
      position: (i + 1).to_f,
      created_at: now, updated_at: now
    )
  end
  groceries = [
    ["Coffee beans", :alice, false],
    ["Pasta + sauce", :bob, false],
    ["Breakfast eggs", :test, true],
    ["Cheese & wine", :charlie, false]
  ]
  groceries.each_with_index do |(content, owner, done), i|
    DB[:task_items].insert_conflict(
      target: :id,
      update: { content: content, completed_at: done ? now - (60 * 60) : nil, updated_at: now }
    ).insert(
      id: det_uuid("task:cabin:groceries:#{i}"),
      task_list_id: cabin_tl_groceries,
      user_id: user_id_for[owner],
      content: content,
      completed_at: done ? now - (60 * 60) : nil,
      position: (i + 1).to_f,
      created_at: now, updated_at: now
    )
  end

  # Expenses: a few entries split across attendees, with non-default factors.
  # `filed_by` shows the on-behalf-of capability: charlie paid for the
  # tasting menu but never logged it; alice filed the expense for him.
  expense_plan = [
    { key: "cabin-rental", desc: "Cabin rental (4 nights)", amount: 480, payer: :test,
      participants: { test: 1, alice: 1, bob: 1, charlie: 1 } },
    { key: "groceries", desc: "Groceries run", amount: 92.40, payer: :alice,
      participants: { test: 1, alice: 1, bob: 1, charlie: 1 } },
    { key: "firewood", desc: "Firewood + kindling", amount: 35, payer: :bob,
      participants: { test: 1, alice: 1, bob: 1, charlie: 1 } },
    { key: "fancy-dinner", desc: "Saturday tasting menu", amount: 220, payer: :charlie, filed_by: :alice,
      participants: { test: 1, alice: 1, charlie: 1.5 } } # bob skipped, charlie ordered the wine pairing
  ]
  expense_ids = {}
  expense_plan.each do |e|
    eid = det_uuid("expense:cabin:#{e[:key]}")
    expense_ids[e[:key]] = eid
    DB[:expenses].insert_conflict(
      target: :id,
      update: { amount: e[:amount], description: e[:desc],
                created_by_user_id: Sequel[:excluded][:created_by_user_id],
                updated_at: now }
    ).insert(
      id: eid,
      event_id: cabin_id,
      user_id: user_id_for[e[:payer]],
      created_by_user_id: user_id_for[e[:filed_by] || e[:payer]],
      amount: e[:amount],
      description: e[:desc],
      start_date: cabin_start,
      end_date: cabin_end,
      created_at: now - (60 * 60 * 24 * 2),
      updated_at: now
    )
    e[:participants].each do |participant, factor|
      DB[:expense_participants].insert_conflict(
        target: %i[expense_id user_id],
        update: { factor: factor, updated_at: now }
      ).insert(
        id: det_uuid("expense_participant:#{e[:key]}:#{participant}"),
        expense_id: eid,
        user_id: user_id_for[participant],
        factor: factor,
        created_at: now,
        updated_at: now
      )
    end
  end

  # Settlements chain: root + a top-up, with transfers in mixed paid/unpaid state.
  root_settlement_id = det_uuid("settlement:cabin:root")
  topup_settlement_id = det_uuid("settlement:cabin:topup")

  rsvp_snapshot_json = Sequel.pg_json(
    rsvps: rsvp_plan.select { |r| r[:attending] }.map do |r|
      { user_id: user_id_for[r[:user]],
        start_date: (r[:start] || cabin_start).iso8601,
        end_date: (r[:finish] || cabin_end).iso8601 }
    end
  )

  DB[:settlements].insert_conflict(
    target: :id,
    update: { rsvp_snapshot: rsvp_snapshot_json, updated_at: now }
  ).insert(
    id: root_settlement_id,
    event_id: cabin_id,
    user_id: user_id_for[:test],
    previous_settlement_id: nil,
    rsvp_snapshot: rsvp_snapshot_json,
    created_at: now - (60 * 60 * 24),
    updated_at: now - (60 * 60 * 24)
  )
  DB[:settlements].insert_conflict(
    target: :id,
    update: { rsvp_snapshot: rsvp_snapshot_json, updated_at: now }
  ).insert(
    id: topup_settlement_id,
    event_id: cabin_id,
    user_id: user_id_for[:test],
    previous_settlement_id: root_settlement_id,
    rsvp_snapshot: rsvp_snapshot_json,
    created_at: now - (60 * 60 * 4),
    updated_at: now - (60 * 60 * 4)
  )
  # Tag the early expenses to the root settlement; the late one belongs to the top-up.
  DB[:expenses]
    .where(id: [expense_ids["cabin-rental"], expense_ids["groceries"], expense_ids["firewood"]])
    .update(settlement_id: root_settlement_id)
  DB[:expenses].where(id: expense_ids["fancy-dinner"]).update(settlement_id: topup_settlement_id)

  # Root transfers: bob already paid, charlie still owes.
  root_transfers = [
    { key: "bob_to_test", from: :bob, to: :test, amount: 96.85, paid: true,
      superseded: now - (60 * 60 * 4) },
    { key: "charlie_to_test", from: :charlie, to: :test, amount: 96.85, paid: false,
      superseded: now - (60 * 60 * 4) },
    { key: "charlie_to_alice", from: :charlie, to: :alice, amount: 23.10, paid: true, superseded: nil }
  ]
  root_transfers.each do |t|
    DB[:settlement_transfers].insert_conflict(
      target: :id,
      update: { amount: t[:amount], paid_at: t[:paid] ? now - (60 * 60 * 12) : nil,
                superseded_at: t[:superseded], updated_at: now }
    ).insert(
      id: det_uuid("transfer:cabin:root:#{t[:key]}"),
      settlement_id: root_settlement_id,
      from_user_id: user_id_for[t[:from]],
      to_user_id: user_id_for[t[:to]],
      amount: t[:amount],
      paid_at: t[:paid] ? now - (60 * 60 * 12) : nil,
      superseded_at: t[:superseded],
      created_at: now - (60 * 60 * 24),
      updated_at: now
    )
  end
  topup_transfers = [
    { key: "bob_to_charlie", from: :bob, to: :charlie, amount: 14.50 },
    { key: "test_to_charlie", from: :test, to: :charlie, amount: 73.33 },
    { key: "alice_to_charlie", from: :alice, to: :charlie, amount: 73.33 }
  ]
  topup_transfers.each do |t|
    DB[:settlement_transfers].insert_conflict(
      target: :id,
      update: { amount: t[:amount], updated_at: now }
    ).insert(
      id: det_uuid("transfer:cabin:topup:#{t[:key]}"),
      settlement_id: topup_settlement_id,
      from_user_id: user_id_for[t[:from]],
      to_user_id: user_id_for[t[:to]],
      amount: t[:amount],
      paid_at: nil,
      superseded_at: nil,
      created_at: now - (60 * 60 * 4),
      updated_at: now - (60 * 60 * 4)
    )
  end

  # Chore roster: cooking + dishes across the four nights for the four attendees.
  cabin_roster_id = det_uuid("roster:cabin")
  DB[:chore_rosters].insert_conflict(
    target: :id,
    update: { updated_at: now }
  ).insert(
    id: cabin_roster_id, event_id: cabin_id, user_id: user_id_for[:test],
    created_at: now, updated_at: now
  )
  chores = [
    { key: "cooking", name: "Cooking dinner", per_day: 1, position: 1.0 },
    { key: "dishes", name: "Dishes", per_day: 1, position: 2.0 },
    { key: "fire", name: "Light the fire", per_day: 1, position: 3.0 }
  ]
  chores.each do |c|
    DB[:chores].insert_conflict(
      target: :id,
      update: { name: c[:name], people_per_day: c[:per_day], position: c[:position], updated_at: now }
    ).insert(
      id: det_uuid("chore:cabin:#{c[:key]}"),
      chore_roster_id: cabin_roster_id,
      name: c[:name],
      people_per_day: c[:per_day],
      position: c[:position],
      created_at: now, updated_at: now
    )
  end
  # Round-robin attendees (excluding diana) across the four days for each chore.
  attendees = %i[test alice bob charlie]
  chores.each do |c|
    chore_id = det_uuid("chore:cabin:#{c[:key]}")
    (cabin_start..cabin_end).each_with_index do |date, idx|
      assignee = attendees[(idx + chores.index(c)) % attendees.size]
      DB[:chore_assignments].insert_conflict(
        target: %i[chore_id user_id date],
        update: { pinned: idx.zero?, updated_at: now }
      ).insert(
        id: det_uuid("assignment:cabin:#{c[:key]}:#{date}:#{assignee}"),
        chore_id: chore_id,
        user_id: user_id_for[assignee],
        date: date,
        pinned: idx.zero?,
        created_at: now, updated_at: now
      )
    end
  end

  # ── Event 2: conference — open date poll, no winner yet ───────────────────
  conf_id = build_event.call(
    :conference,
    name: "Team offsite — Q3 planning",
    description: "Two-day strategy session. Need to lock dates by end of week.",
    owner: :alice,
    location: "Brussels"
  )
  conf_poll_id = det_uuid("poll:conference")
  DB[:date_polls].insert_conflict(
    target: :id,
    update: { deadline: now + (60 * 60 * 24 * 5), updated_at: now }
  ).insert(
    id: conf_poll_id, event_id: conf_id,
    deadline: now + (60 * 60 * 24 * 5),
    closed_at: nil, selected_date_range_id: nil,
    created_at: now - (60 * 60 * 24 * 2), updated_at: now
  )
  conf_options = [
    { key: "early-jun", start: today + 28, finish: today + 29 },
    { key: "mid-jun", start: today + 35, finish: today + 36 },
    { key: "late-jun", start: today + 42, finish: today + 43 }
  ]
  conf_options.each do |opt|
    DB[:date_ranges].insert_conflict(
      target: :id,
      update: { start_date: opt[:start], end_date: opt[:finish], updated_at: now }
    ).insert(
      id: det_uuid("daterange:conf:#{opt[:key]}"),
      date_poll_id: conf_poll_id,
      start_date: opt[:start], end_date: opt[:finish],
      created_at: now - (60 * 60 * 24 * 2), updated_at: now
    )
  end
  partial_votes = [
    { user: :test, key: "mid-jun", response: "yes" },
    { user: :test, key: "late-jun", response: "preferably_not" },
    { user: :alice, key: "early-jun", response: "yes" },
    { user: :alice, key: "mid-jun", response: "yes" },
    { user: :bob, key: "late-jun", response: "yes", comment: "Can't do mid-month." }
  ]
  partial_votes.each do |v|
    DB[:votes].insert_conflict(
      target: %i[date_range_id user_id],
      update: { response: v[:response], comment: v[:comment], updated_at: now }
    ).insert(
      id: det_uuid("vote:conf:#{v[:user]}:#{v[:key]}"),
      date_range_id: det_uuid("daterange:conf:#{v[:key]}"),
      user_id: user_id_for[v[:user]],
      response: v[:response],
      comment: v[:comment],
      created_at: now - (60 * 60 * 12), updated_at: now
    )
  end

  # ── Event 3: birthday — bare-bones, just so empty-state UIs aren't always empty ─
  bday_id = build_event.call(
    :birthday,
    name: "Diana's birthday drinks",
    description: "Casual hangout at the bar around the corner.",
    owner: :diana,
    start_date: today + 4,
    end_date: today + 4,
    location: "Café Bonjour, Brussels"
  )
  bday_tl = det_uuid("tasklist:birthday:bring")
  DB[:task_lists].insert_conflict(
    target: :id,
    update: { name: "Stuff to bring", updated_at: now }
  ).insert(
    id: bday_tl, workspace_id: workspace_id, user_id: user_id_for[:diana],
    name: "Stuff to bring", position: 1.0,
    created_at: now, updated_at: now
  )
  ["Cake candles", "Birthday card", "Bluetooth speaker"].each_with_index do |content, i|
    DB[:task_items].insert_conflict(
      target: :id,
      update: { content: content, updated_at: now }
    ).insert(
      id: det_uuid("task:birthday:#{i}"),
      task_list_id: bday_tl, user_id: nil,
      content: content, completed_at: nil,
      position: (i + 1).to_f,
      created_at: now, updated_at: now
    )
  end
  # Event-level RSVP only — no date poll for this one (event has fixed dates).
  %i[test alice bob charlie diana].each do |u|
    DB[:rsvps].insert_conflict(
      target: %i[event_id user_id],
      update: { updated_at: now }
    ).insert(
      id: det_uuid("rsvp:birthday:#{u}"),
      event_id: bday_id, user_id: user_id_for[u],
      attending: u != :charlie,
      start_date: nil, end_date: nil,
      created_at: now, updated_at: now
    )
  end

  # ── Event 4: bowling night — shows multi-event netting on Settle Up ──────
  # Test fronted the lanes; charlie + alice each owe ~€20. That charlie→test
  # transfer offsets the cabin's test→charlie 73.33 in the workspace-level
  # Settle Up view, so the netted obligation between test and charlie shrinks
  # (and the per-event breakdown shows one row in each direction).
  bowl_date = today - 7
  bowl_id = build_event.call(
    :bowling,
    name: "Friday bowling night",
    description: "Lanes were on test — we'll settle up with the cabin trip in one go.",
    owner: :alice,
    start_date: bowl_date,
    end_date: bowl_date,
    location: "Bowling alley downtown"
  )

  bowl_attending = %i[test alice charlie]
  (bowl_attending + %i[bob diana]).each do |u|
    attending = bowl_attending.include?(u)
    DB[:rsvps].insert_conflict(
      target: %i[event_id user_id],
      update: { attending: attending, updated_at: now }
    ).insert(
      id: det_uuid("rsvp:bowling:#{u}"),
      event_id: bowl_id,
      user_id: user_id_for[u],
      created_by_user_id: user_id_for[u],
      attending: attending,
      start_date: nil, end_date: nil,
      created_at: now - (60 * 60 * 24 * 8),
      updated_at: now
    )
  end

  bowl_expense_id = det_uuid("expense:bowling:lanes")
  DB[:expenses].insert_conflict(
    target: :id,
    update: { amount: 60.00, description: "Lane rental and shoes",
              created_by_user_id: Sequel[:excluded][:created_by_user_id],
              updated_at: now }
  ).insert(
    id: bowl_expense_id,
    event_id: bowl_id,
    user_id: user_id_for[:test],
    created_by_user_id: user_id_for[:test],
    amount: 60.00,
    description: "Lane rental and shoes",
    start_date: bowl_date,
    end_date: bowl_date,
    created_at: now - (60 * 60 * 24 * 7),
    updated_at: now
  )
  bowl_attending.each do |u|
    DB[:expense_participants].insert_conflict(
      target: %i[expense_id user_id],
      update: { factor: 1, updated_at: now }
    ).insert(
      id: det_uuid("expense_participant:bowling:#{u}"),
      expense_id: bowl_expense_id,
      user_id: user_id_for[u],
      factor: 1,
      created_at: now - (60 * 60 * 24 * 7),
      updated_at: now
    )
  end

  bowl_settlement_id = det_uuid("settlement:bowling:root")
  bowl_rsvp_snapshot = Sequel.pg_json(
    rsvps: bowl_attending.map do |u|
      { user_id: user_id_for[u], start_date: bowl_date.iso8601, end_date: bowl_date.iso8601 }
    end
  )
  DB[:settlements].insert_conflict(
    target: :id,
    update: { rsvp_snapshot: bowl_rsvp_snapshot, updated_at: now }
  ).insert(
    id: bowl_settlement_id,
    event_id: bowl_id,
    user_id: user_id_for[:test],
    previous_settlement_id: nil,
    rsvp_snapshot: bowl_rsvp_snapshot,
    created_at: now - (60 * 60 * 24 * 6),
    updated_at: now - (60 * 60 * 24 * 6)
  )
  DB[:expenses].where(id: bowl_expense_id).update(settlement_id: bowl_settlement_id)

  # Both unpaid so they show up live on the Settle Up page. The charlie→test
  # one is the punchline: it nets against cabin's test→charlie 73.33.
  [
    { key: "alice_to_test", from: :alice, to: :test, amount: 20.00 },
    { key: "charlie_to_test", from: :charlie, to: :test, amount: 20.00 }
  ].each do |t|
    DB[:settlement_transfers].insert_conflict(
      target: :id,
      update: { amount: t[:amount], paid_at: nil, superseded_at: nil, updated_at: now }
    ).insert(
      id: det_uuid("transfer:bowling:#{t[:key]}"),
      settlement_id: bowl_settlement_id,
      from_user_id: user_id_for[t[:from]],
      to_user_id: user_id_for[t[:to]],
      amount: t[:amount],
      paid_at: nil,
      superseded_at: nil,
      created_at: now - (60 * 60 * 24 * 6),
      updated_at: now - (60 * 60 * 24 * 6)
    )
  end

  # ── Event 5: dinner — gives test an unconditional debt for the QR modal ──
  # Diana fronted a two-person tasting menu for herself and test. The single
  # test→diana transfer is independent of the cabin/bowling chain, so even
  # if those have been further-settled in the dev DB, this one keeps test
  # in the role of net sender — useful for exercising the Pay via QR flow.
  dinner_date = today - 3
  dinner_id = build_event.call(
    :dinner,
    name: "Tasting menu at Bouchon",
    description: "Diana put it on her card; test owes her half.",
    owner: :diana,
    start_date: dinner_date,
    end_date: dinner_date,
    location: "Restaurant Bouchon, Brussels"
  )

  dinner_attending = %i[test diana]
  (dinner_attending + %i[alice bob charlie]).each do |u|
    attending = dinner_attending.include?(u)
    DB[:rsvps].insert_conflict(
      target: %i[event_id user_id],
      update: { attending: attending, updated_at: now }
    ).insert(
      id: det_uuid("rsvp:dinner:#{u}"),
      event_id: dinner_id,
      user_id: user_id_for[u],
      created_by_user_id: user_id_for[u],
      attending: attending,
      start_date: nil, end_date: nil,
      created_at: now - (60 * 60 * 24 * 5),
      updated_at: now
    )
  end

  dinner_expense_id = det_uuid("expense:dinner:tasting-menu")
  DB[:expenses].insert_conflict(
    target: :id,
    update: { amount: 120.00, description: "Tasting menu for two",
              created_by_user_id: Sequel[:excluded][:created_by_user_id],
              updated_at: now }
  ).insert(
    id: dinner_expense_id,
    event_id: dinner_id,
    user_id: user_id_for[:diana],
    created_by_user_id: user_id_for[:diana],
    amount: 120.00,
    description: "Tasting menu for two",
    start_date: dinner_date,
    end_date: dinner_date,
    created_at: now - (60 * 60 * 24 * 3),
    updated_at: now
  )
  dinner_attending.each do |u|
    DB[:expense_participants].insert_conflict(
      target: %i[expense_id user_id],
      update: { factor: 1, updated_at: now }
    ).insert(
      id: det_uuid("expense_participant:dinner:#{u}"),
      expense_id: dinner_expense_id,
      user_id: user_id_for[u],
      factor: 1,
      created_at: now - (60 * 60 * 24 * 3),
      updated_at: now
    )
  end

  dinner_settlement_id = det_uuid("settlement:dinner:root")
  dinner_rsvp_snapshot = Sequel.pg_json(
    rsvps: dinner_attending.map do |u|
      { user_id: user_id_for[u], start_date: dinner_date.iso8601, end_date: dinner_date.iso8601 }
    end
  )
  DB[:settlements].insert_conflict(
    target: :id,
    update: { rsvp_snapshot: dinner_rsvp_snapshot, updated_at: now }
  ).insert(
    id: dinner_settlement_id,
    event_id: dinner_id,
    user_id: user_id_for[:diana],
    previous_settlement_id: nil,
    rsvp_snapshot: dinner_rsvp_snapshot,
    created_at: now - (60 * 60 * 24 * 2),
    updated_at: now - (60 * 60 * 24 * 2)
  )
  DB[:expenses].where(id: dinner_expense_id).update(settlement_id: dinner_settlement_id)

  DB[:settlement_transfers].insert_conflict(
    target: :id,
    update: { amount: 60.00, paid_at: nil, superseded_at: nil, updated_at: now }
  ).insert(
    id: det_uuid("transfer:dinner:test_to_diana"),
    settlement_id: dinner_settlement_id,
    from_user_id: user_id_for[:test],
    to_user_id: user_id_for[:diana],
    amount: 60.00,
    paid_at: nil,
    superseded_at: nil,
    created_at: now - (60 * 60 * 24 * 2),
    updated_at: now - (60 * 60 * 24 * 2)
  )

  # Suppress unused-variable warning while keeping the assignment for clarity.
  _ = conf_id
end

puts "Seeded development data:"
puts "  Workspace: Friends & Family (#{workspace_id})"
puts "  Users: #{users.values.map { |u| u[:email] }.join(", ")}"
puts "  Events: cabin trip (settled with chores), team offsite (open poll), birthday drinks, Friday bowling night (multi-event netting), tasting-menu dinner (test owes diana — QR demo)"
puts ""
puts "Log in as #{users[:test][:email]} via the magic-link flow."
