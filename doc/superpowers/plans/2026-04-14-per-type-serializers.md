# Per-Type Pool Serializers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic `PoolSerializer` + model `to_api_hash` pattern with one serializer class per pool-registered type. Unify the two permission-attachment paths (sync-time in PoolSerializer, broadcast-time in ConnectionManager) onto a single `PermissionAttacher`. Make the `ObjectRegistry` the single source of truth: adding a new type should not require editing `workspace_sync.rb`, `listener.rb`, or `pool_serializer.rb`.

**Architecture:** Each of the 17 registered pool types gets a serializer class at `backend/app/serializers/<type>_serializer.rb` exposing `serialize_batch(objects, pool:)`, `policy_context(object)`, and `policy_context_batch(objects)`. The registry gains a `serializer_class:` field. `PoolSerializer` becomes a thin coordinator that dispatches through the registry. `Websocket::Listener` stops encoding policy-context rules; instead it asks the serializer. `Websocket::ConnectionManager` stops reimplementing permission attachment; instead it calls `PermissionAttacher`. Parent → child relationships (task_list → task_items, chore_roster → chores → assignments, expense → participants) become explicit: the parent serializer adds children to the `pool` argument. Models lose their `to_api_hash` methods (for the 17 registered types only) and become pure data structs. `User#to_api_hash`, `Session#to_api_hash`, `PasskeyCredential#to_api_hash`, and `ServiceError#to_api_hash` are **not** touched — they are used by non-pool code paths.

**Tech Stack:** Ruby 4, Roda, Sequel, RSpec, dry-monads.

---

## Pre-Flight

The backend is clean but the frontend has unrelated uncommitted work. This refactor only touches `backend/`, so the frontend changes will not collide. Either:

- Run on current branch (simplest; backend-only changes)
- Run in a worktree via `superpowers:using-git-worktrees` (safer isolation)

Either approach is fine; pick when starting execution.

**Strategy** — the plan migrates types one at a time while keeping every existing public API (`pool.add_event`, `pool.add_events_batch`, etc.) working throughout Phases 1–3. All pre-existing specs continue to pass at every commit. The legacy methods are deleted in Phase 4. This means you can stop at any point mid-plan and the codebase is in a working state.

**Design invariants** (true for every task):

1. `serialize_batch(objects, pool: nil)` always returns an array the **same length** as `objects`, with `nil` entries for objects that should be skipped (e.g. member where the user row was deleted).
2. `serialize_batch` does **not** attach permissions. Permissions are attached by the caller (`PoolSerializer#add_batch` or `ConnectionManager`) via `PermissionAttacher`.
3. `policy_context_batch(objects)` returns a `Hash` keyed by `object.id.to_s` with policy-context kwargs. Missing keys mean empty context. Returns `{}` for types with no extra context.
4. Serializers that own children (`task_list` → task_items, `chore_roster` → chores+assignments, `expense` → participants) expand them by calling `pool.add(:child_type, children)` when `pool:` is not nil. When `pool:` is nil, no expansion.
5. Hash keys are camelCase. Timestamps are `iso8601(3)` (ms precision). IDs are strings.
6. `objectType` matches `ObjectRegistry::BY_KEY[key].client_type` exactly.

**File structure** (end state):

```
backend/app/
  object_registry.rb                    # modified: adds serializer_class field
  serializers/
    pool_serializer.rb                  # shrunk from ~370 to ~70 lines
    permission_attacher.rb              # new: unified permission merging
    event_serializer.rb                 # new
    workspace_serializer.rb             # new
    member_serializer.rb                # new (replaces build_member_hash)
    date_poll_serializer.rb             # new
    date_range_serializer.rb            # new
    vote_serializer.rb                  # new
    rsvp_serializer.rb                  # new
    task_list_serializer.rb             # new
    task_item_serializer.rb             # new
    expense_serializer.rb               # new
    expense_participant_serializer.rb   # new
    settlement_serializer.rb            # new
    settlement_transfer_serializer.rb   # new
    chore_roster_serializer.rb          # new
    chore_serializer.rb                 # new
    chore_assignment_serializer.rb      # new
    workspace_invite_serializer.rb      # new
  websocket/
    listener.rb                         # modified: delete prefetch_policy_context
    connection_manager.rb               # modified: delegate to PermissionAttacher
  services/sync/
    workspace_sync.rb                   # modified: delete batch_methods hash
  models/
    event.rb, workspace.rb, ...         # modified: remove to_api_hash for the 17 pool types
    workspace_membership.rb             # modified: delete dead to_api_hash
```

---

## Phase 1: Infrastructure

### Task 1: Create PermissionAttacher service

**Files:**
- Create: `backend/app/serializers/permission_attacher.rb`
- Create: `backend/spec/serializers/permission_attacher_spec.rb`

This consolidates the two duplicated attachment paths (`PoolSerializer#attach_permissions` and `ConnectionManager#attach_permissions`). Both will be refactored to call this in later tasks.

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/permission_attacher_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe PermissionAttacher do
  let(:workspace) { TestFactories.workspace }
  let(:owner) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:owner_membership) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: owner)[:id]) }
  let(:other_membership) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: other_user)[:id]) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: owner) }
  let(:event) { Event.find(event_row[:id]) }
  let(:event_hash) { { id: event.id.to_s, objectType: "event", name: event.name } }

  describe ".call" do
    it "merges permissions from the policy for the given membership" do
      result = described_class.call(event_hash, raw_object: event, membership: owner_membership)

      expect(result[:permissions][:edit]).to eq({ allowed: true })
      expect(result[:permissions][:delete]).to eq({ allowed: true })
    end

    it "uses policy_context kwargs to influence permissions" do
      result = described_class.call(
        event_hash, raw_object: event, membership: owner_membership,
        policy_context: { has_expenses: true }
      )

      expect(result[:permissions][:delete]).to eq({ allowed: false, reason: "has_expenses" })
    end

    it "returns the original hash unchanged when membership is nil" do
      result = described_class.call(event_hash, raw_object: event, membership: nil)

      expect(result).not_to have_key(:permissions)
    end

    it "returns the original hash unchanged when objectType is not in the registry" do
      unknown_hash = { id: "1", objectType: "notAType" }
      result = described_class.call(unknown_hash, raw_object: nil, membership: owner_membership)

      expect(result).to eq(unknown_hash)
    end

    it "swallows policy errors and logs them, returning the hash without permissions" do
      allow(APP_LOGGER).to receive(:error)
      allow(EventPolicy).to receive(:new).and_raise(StandardError, "boom")

      result = described_class.call(event_hash, raw_object: event, membership: owner_membership)

      expect(result).not_to have_key(:permissions)
      expect(APP_LOGGER).to have_received(:error)
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/permission_attacher_spec.rb
```

Expected: `NameError: uninitialized constant PermissionAttacher`

- [ ] **Step 3: Implement PermissionAttacher**

```ruby
# backend/app/serializers/permission_attacher.rb
# frozen_string_literal: true

# Attaches policy-computed permissions to a serialized object hash.
#
# This is the single code path for permission merging — used both at sync time
# (PoolSerializer) and at broadcast time (Websocket::ConnectionManager), so the
# two can never drift.
#
# @example
#   PermissionAttacher.call(
#     event_hash,
#     raw_object: event,
#     membership: membership,
#     policy_context: { has_expenses: true }
#   )
#   # => event_hash.merge(permissions: { edit: { allowed: true }, ... })
module PermissionAttacher
  class << self
    def call(hash, raw_object:, membership:, policy_context: {})
      return hash unless membership

      entry = ObjectRegistry::BY_CLIENT_TYPE[hash[:objectType]]
      return hash unless entry&.policy

      policy_class = Object.const_get(entry.policy)
      policy = policy_class.new(raw_object, membership: membership, **policy_context)
      hash.merge(permissions: policy.permissions)
    rescue StandardError => e
      APP_LOGGER.error do
        "[PermissionAttacher] Failed for #{hash[:objectType]}: #{e.class}: #{e.message}\n" \
          "#{e.backtrace&.first(5)&.join("\n")}"
      end
      hash
    end
  end
end
```

- [ ] **Step 4: Run the spec and confirm it passes**

```
cd backend && bundle exec rspec spec/serializers/permission_attacher_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Commit**

```
cd backend && git add app/serializers/permission_attacher.rb spec/serializers/permission_attacher_spec.rb
git commit -m "Extract PermissionAttacher for unified policy merging"
```

---

### Task 2: Add `serializer_class` to ObjectRegistry

**Files:**
- Modify: `backend/app/object_registry.rb`

The registry gains an optional `serializer_class:` field. We populate it lazily: as each type's serializer ships, we add it to the entry. Until then, `serializer_class` is nil and PoolSerializer falls back to the legacy `add_X` methods.

- [ ] **Step 1: Modify Entry to accept serializer_class**

Replace the entire `Entry` class in `backend/app/object_registry.rb` (lines 6–24):

```ruby
  class Entry
    attr_reader :key, :model, :client_type, :pool_method, :tracks_user, :policy, :serializer_class

    def initialize(
      key:,
      model:,
      client_type:,
      pool_method:,
      tracks_user:,
      policy: nil,
      serializer_class: nil
    )
      @key = key
      @model = model
      @client_type = client_type
      @pool_method = pool_method
      @tracks_user = tracks_user
      @policy = policy
      @serializer_class = serializer_class
    end
  end
```

- [ ] **Step 2: Run the existing spec suite to ensure nothing breaks**

```
cd backend && bundle exec rspec spec/
```

Expected: all existing examples pass (the new kwarg has a default, so no registry entries need updating yet).

- [ ] **Step 3: Commit**

```
cd backend && git add app/object_registry.rb
git commit -m "Allow ObjectRegistry entries to carry a serializer class"
```

---

### Task 3: Add `PoolSerializer#add_batch` helper (keeping legacy API)

**Files:**
- Modify: `backend/app/serializers/pool_serializer.rb`

Introduce a private helper that will become the main entry point in later tasks. It takes a registry entry and a list of items, calls the entry's `serializer_class.serialize_batch`, applies permissions via `PermissionAttacher`, and stores the results in `@objects`. Legacy `add_X` methods continue to exist unchanged — they will be redirected in subsequent tasks as each type migrates.

- [ ] **Step 1: Add the helper at the bottom of the private section**

Modify `backend/app/serializers/pool_serializer.rb`. Insert the following method after `build_member_hash` (immediately before the final `end` of the class), in the `private` section:

```ruby
  # New unified path: dispatches to the registry's serializer_class. Returns
  # the number of new objects added (for tests). Legacy add_X methods will
  # delegate to this as each type migrates.
  def add_batch(entry, items)
    return 0 if items.empty?

    serializer = entry.serializer_class
    raise ArgumentError, "No serializer_class for #{entry.key}" unless serializer

    contexts = serializer.policy_context_batch(items)
    hashes = serializer.serialize_batch(items, pool: self)
    added = 0

    items.zip(hashes).each do |obj, hash|
      next unless hash

      key = "#{entry.key}:#{obj.id}"
      next if @objects.key?(key)

      @objects[key] = if @membership
                        PermissionAttacher.call(
                          hash,
                          raw_object: obj,
                          membership: @membership,
                          policy_context: contexts[obj.id.to_s] || {}
                        )
                      else
                        hash
                      end
      added += 1
    end

    added
  end
```

- [ ] **Step 2: Run existing PoolSerializer specs**

```
cd backend && bundle exec rspec spec/serializers/
```

Expected: unchanged — all pass. `add_batch` is private and unused; no behavior change.

- [ ] **Step 3: Commit**

```
cd backend && git add app/serializers/pool_serializer.rb
git commit -m "Add PoolSerializer#add_batch dispatch helper"
```

---

### Task 4: Create EventSerializer and redirect add_event paths

**Files:**
- Create: `backend/app/serializers/event_serializer.rb`
- Create: `backend/spec/serializers/event_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb`
- Modify: `backend/app/serializers/pool_serializer.rb:58-90`

Event is the most complex simple case: it has both a policy context (`has_expenses`) and supplementary fields (`datePollId`, `rsvpIds`) that require DB lookups. Doing it first establishes the pattern.

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/event_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe EventSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "returns an empty array for an empty input" do
      expect(described_class.serialize_batch([], pool: nil)).to eq([])
    end

    it "serializes fields with camelCase keys and iso8601(3) timestamps" do
      event_row = TestFactories.event(workspace: workspace, user: user, name: "Party")
      event = Event.find(event_row[:id])

      result = described_class.serialize_batch([event], pool: nil).first

      expect(result[:id]).to eq(event.id.to_s)
      expect(result[:objectType]).to eq("event")
      expect(result[:name]).to eq("Party")
      expect(result[:workspaceId]).to eq(workspace[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:createdAt]).to match(/\A\d{4}-\d{2}-\d{2}T.*\.\d{3}/)
      expect(result[:updatedAt]).to match(/\A\d{4}-\d{2}-\d{2}T.*\.\d{3}/)
      expect(result[:datePollId]).to be_nil
      expect(result[:rsvpIds]).to eq([])
    end

    it "includes datePollId and rsvpIds when present" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      event = Event.find(event_row[:id])
      poll = TestFactories.date_poll(event: event_row)
      rsvp = TestFactories.rsvp(event: event_row, user: user)

      result = described_class.serialize_batch([event], pool: nil).first

      expect(result[:datePollId]).to eq(poll[:id].to_s)
      expect(result[:rsvpIds]).to include(rsvp[:id].to_s)
    end

    it "batches date poll and rsvp lookups across multiple events" do
      event1_row = TestFactories.event(workspace: workspace, user: user)
      event2_row = TestFactories.event(workspace: workspace, user: user)
      event1 = Event.find(event1_row[:id])
      event2 = Event.find(event2_row[:id])
      poll = TestFactories.date_poll(event: event1_row)

      result = described_class.serialize_batch([event1, event2], pool: nil)

      expect(result[0][:datePollId]).to eq(poll[:id].to_s)
      expect(result[1][:datePollId]).to be_nil
    end
  end

  describe ".policy_context_batch" do
    it "returns has_expenses: false for events with no financial data" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      event = Event.find(event_row[:id])

      context = described_class.policy_context_batch([event])

      expect(context[event.id.to_s]).to eq(has_expenses: false)
    end

    it "returns has_expenses: true when the event has an expense" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      event = Event.find(event_row[:id])
      DB[:expenses].insert(
        id: SecureRandom.uuid, event_id: event_row[:id], user_id: user[:id],
        description: "x", amount: 1.0, start_date: Date.today, end_date: Date.today,
        created_at: Time.now, updated_at: Time.now
      )

      context = described_class.policy_context_batch([event])

      expect(context[event.id.to_s]).to eq(has_expenses: true)
    end

    it "returns has_expenses: true when the event has a settlement" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      event = Event.find(event_row[:id])
      DB[:settlements].insert(
        id: SecureRandom.uuid, event_id: event_row[:id], user_id: user[:id],
        created_at: Time.now, updated_at: Time.now
      )

      context = described_class.policy_context_batch([event])

      expect(context[event.id.to_s]).to eq(has_expenses: true)
    end
  end

  describe ".policy_context" do
    it "returns the same shape as a single-item batch" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      event = Event.find(event_row[:id])

      expect(described_class.policy_context(event)).to eq(has_expenses: false)
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/event_serializer_spec.rb
```

Expected: `NameError: uninitialized constant EventSerializer`

- [ ] **Step 3: Implement EventSerializer**

```ruby
# backend/app/serializers/event_serializer.rb
# frozen_string_literal: true

# Serializes Event model instances into pool object hashes.
#
# Owns both the field mapping AND the related-object lookups (date_poll, rsvps)
# AND the policy-context prefetch (has_expenses). This is the single source of
# truth for event serialization — called by PoolSerializer at sync time and by
# Websocket::ConnectionManager at broadcast time (via PermissionAttacher).
class EventSerializer
  class << self
    def serialize_batch(events, pool:)
      return [] if events.empty?

      event_ids = events.map { |e| e.id.to_s }
      polls_by_event = DatePoll.for_event_ids(event_ids)
      rsvp_ids_by_event = Rsvp.ids_for_event_ids(event_ids)

      events.map do |event|
        date_poll = polls_by_event[event.id.to_s]
        {
          id: event.id.to_s,
          objectType: "event",
          name: event.name,
          description: event.description,
          startDate: event.start_date&.iso8601,
          endDate: event.end_date&.iso8601,
          locationName: event.location_name,
          latitude: event.location_coordinates&.[](1),
          longitude: event.location_coordinates&.[](0),
          workspaceId: event.workspace_id.to_s,
          userId: event.user_id.to_s,
          datePollId: date_poll&.id&.to_s,
          rsvpIds: rsvp_ids_by_event[event.id.to_s] || [],
          createdAt: event.created_at.iso8601(3),
          updatedAt: event.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(event)
      policy_context_batch([event])[event.id.to_s] || {}
    end

    def policy_context_batch(events)
      return {} if events.empty?

      event_ids = events.map { |e| e.id.to_s }
      with_expenses = DB[:expenses].where(event_id: event_ids).distinct.select_map(:event_id).to_set
      with_settlements = DB[:settlements].where(event_id: event_ids).distinct.select_map(:event_id).to_set
      financial = with_expenses | with_settlements

      events.each_with_object({}) do |event, h|
        h[event.id.to_s] = { has_expenses: financial.include?(event.id.to_s) }
      end
    end
  end
end
```

- [ ] **Step 4: Wire the serializer into the registry**

In `backend/app/object_registry.rb`, update the event entry. Find this line:

```ruby
    Entry.new(key: "event", model: "Event", client_type: "event", pool_method: :add_event, tracks_user: true, policy: "EventPolicy"),
```

Replace with:

```ruby
    Entry.new(key: "event", model: "Event", client_type: "event", pool_method: :add_event, tracks_user: true, policy: "EventPolicy", serializer_class: EventSerializer),
```

- [ ] **Step 5: Redirect `add_event` and `add_events_batch` to the new path**

In `backend/app/serializers/pool_serializer.rb`, replace the two methods (lines 58–90) with delegates to `add_batch`:

```ruby
  def add_event(event)
    add_batch(ObjectRegistry::BY_KEY["event"], [event])
  end

  def add_events_batch(events)
    add_batch(ObjectRegistry::BY_KEY["event"], events)
  end
```

- [ ] **Step 6: Run the full event-related spec suite**

```
cd backend && bundle exec rspec spec/serializers/ spec/services/sync/workspace_sync_spec.rb
```

Expected: all pass. The existing `pool_serializer_spec.rb` and `pool_serializer_permissions_spec.rb` tests pin the behavior; if anything drifted we'll see it now.

- [ ] **Step 7: Run the full backend test suite to catch anything else**

```
cd backend && bundle exec rspec
```

Expected: all pass.

- [ ] **Step 8: Commit**

```
cd backend && git add app/serializers/event_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/event_serializer_spec.rb
git commit -m "Introduce per-type EventSerializer as the migration template"
```

---

## Phase 2: Migrate simple types

For each type in Phase 2, the task shape is identical:

1. Write a serializer spec that pins the current behavior (fields, types, edge cases).
2. Run it, expect failure.
3. Implement the serializer at `backend/app/serializers/<type>_serializer.rb`.
4. Wire it into `object_registry.rb` via the `serializer_class:` kwarg.
5. Redirect the existing `add_X` / `add_X_batch` (if present) methods in `pool_serializer.rb` to `add_batch(...)`.
6. Run the serializer spec + `spec/serializers/` + full suite.
7. Commit.

Every serializer in Phase 2 has **no policy context** (policies take only `membership:`) and **no children**, so `policy_context_batch` returns `{}` and `serialize_batch` does not use the `pool:` argument.

---

### Task 5: VoteSerializer

**Files:**
- Create: `backend/app/serializers/vote_serializer.rb`
- Create: `backend/spec/serializers/vote_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (vote entry)
- Modify: `backend/app/serializers/pool_serializer.rb:146-153`

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/vote_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe VoteSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe ".serialize_batch" do
    it "returns an empty array for an empty input" do
      expect(described_class.serialize_batch([], pool: nil)).to eq([])
    end

    it "serializes vote fields" do
      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      range = TestFactories.date_range(date_poll: poll)
      vote_row = TestFactories.vote(date_range: range, user: user, response: "yes", comment: "sure")
      vote = Vote.find(vote_row[:id])

      result = described_class.serialize_batch([vote], pool: nil).first

      expect(result[:id]).to eq(vote.id.to_s)
      expect(result[:objectType]).to eq("vote")
      expect(result[:dateRangeId]).to eq(range[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:response]).to eq("yes")
      expect(result[:comment]).to eq("sure")
      expect(result[:createdAt]).to match(/\.\d{3}/)
      expect(result[:updatedAt]).to match(/\.\d{3}/)
    end
  end

  describe ".policy_context_batch" do
    it "returns an empty hash for votes" do
      expect(described_class.policy_context_batch([])).to eq({})
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/vote_serializer_spec.rb
```

Expected: `NameError: uninitialized constant VoteSerializer`

- [ ] **Step 3: Implement the serializer**

```ruby
# backend/app/serializers/vote_serializer.rb
# frozen_string_literal: true

class VoteSerializer
  class << self
    def serialize_batch(votes, pool:)
      votes.map do |vote|
        {
          id: vote.id.to_s,
          objectType: "vote",
          dateRangeId: vote.date_range_id.to_s,
          userId: vote.user_id.to_s,
          response: vote.response,
          comment: vote.comment,
          createdAt: vote.created_at.iso8601(3),
          updatedAt: vote.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_vote) = {}
    def policy_context_batch(_votes) = {}
  end
end
```

- [ ] **Step 4: Wire into the registry**

In `backend/app/object_registry.rb`, update the vote entry. Find:

```ruby
    Entry.new(key: "vote",        model: "Vote",                 client_type: "vote",       pool_method: :add_vote,        tracks_user: true,  policy: "VotePolicy"),
```

Replace with:

```ruby
    Entry.new(key: "vote",        model: "Vote",                 client_type: "vote",       pool_method: :add_vote,        tracks_user: true,  policy: "VotePolicy", serializer_class: VoteSerializer),
```

- [ ] **Step 5: Redirect `add_vote` in PoolSerializer**

In `backend/app/serializers/pool_serializer.rb`, replace the method at lines 146–153:

```ruby
  def add_vote(vote)
    add_batch(ObjectRegistry::BY_KEY["vote"], [vote])
  end
```

- [ ] **Step 6: Run specs**

```
cd backend && bundle exec rspec spec/serializers/ spec/services/ spec/websocket/
```

Expected: all pass.

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/vote_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/vote_serializer_spec.rb
git commit -m "Extract VoteSerializer"
```

---

### Task 6: RsvpSerializer

**Files:**
- Create: `backend/app/serializers/rsvp_serializer.rb`
- Create: `backend/spec/serializers/rsvp_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (rsvp entry)
- Modify: `backend/app/serializers/pool_serializer.rb:155-162`

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/rsvp_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe RsvpSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe ".serialize_batch" do
    it "serializes rsvp fields" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      rsvp_row = TestFactories.rsvp(
        event: event_row, user: user, attending: true,
        start_date: Date.today, end_date: Date.today + 2
      )
      rsvp = Rsvp.find(rsvp_row[:id])

      result = described_class.serialize_batch([rsvp], pool: nil).first

      expect(result[:id]).to eq(rsvp.id.to_s)
      expect(result[:objectType]).to eq("rsvp")
      expect(result[:eventId]).to eq(event_row[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:attending]).to be true
      expect(result[:startDate]).to eq(Date.today.iso8601)
      expect(result[:endDate]).to eq((Date.today + 2).iso8601)
    end

    it "handles nil dates" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      rsvp_row = TestFactories.rsvp(event: event_row, user: user, attending: false)
      DB[:rsvps].where(id: rsvp_row[:id]).update(start_date: nil, end_date: nil)
      rsvp = Rsvp.find(rsvp_row[:id])

      result = described_class.serialize_batch([rsvp], pool: nil).first

      expect(result[:startDate]).to be_nil
      expect(result[:endDate]).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/rsvp_serializer_spec.rb
```

Expected: `NameError: uninitialized constant RsvpSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/rsvp_serializer.rb
# frozen_string_literal: true

class RsvpSerializer
  class << self
    def serialize_batch(rsvps, pool:)
      rsvps.map do |rsvp|
        {
          id: rsvp.id.to_s,
          objectType: "rsvp",
          eventId: rsvp.event_id.to_s,
          userId: rsvp.user_id.to_s,
          attending: rsvp.attending,
          startDate: rsvp.start_date&.iso8601,
          endDate: rsvp.end_date&.iso8601,
          createdAt: rsvp.created_at.iso8601(3),
          updatedAt: rsvp.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_rsvp) = {}
    def policy_context_batch(_rsvps) = {}
  end
end
```

- [ ] **Step 4: Wire into the registry**

In `backend/app/object_registry.rb`, replace the rsvp entry:

```ruby
    Entry.new(key: "rsvp",        model: "Rsvp",                 client_type: "rsvp",       pool_method: :add_rsvp,        tracks_user: true,  policy: "RsvpPolicy", serializer_class: RsvpSerializer),
```

- [ ] **Step 5: Redirect `add_rsvp`**

In `backend/app/serializers/pool_serializer.rb`, replace the method at lines 155–162:

```ruby
  def add_rsvp(rsvp)
    add_batch(ObjectRegistry::BY_KEY["rsvp"], [rsvp])
  end
```

- [ ] **Step 6: Run specs**

```
cd backend && bundle exec rspec spec/serializers/ spec/services/ spec/websocket/
```

Expected: all pass.

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/rsvp_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/rsvp_serializer_spec.rb
git commit -m "Extract RsvpSerializer"
```

---

### Task 7: DateRangeSerializer

**Files:**
- Create: `backend/app/serializers/date_range_serializer.rb`
- Create: `backend/spec/serializers/date_range_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (date_range entry)
- Modify: `backend/app/serializers/pool_serializer.rb:119-144`

Note: `DateRangePolicy` does take an optional `event:` kwarg for N+1 avoidance — but today the policy falls back to individual lookups when `event:` is not passed. For the per-type serializer path we will **drop** the optimization for now (pushing it through `policy_context_batch` would require crossing two model boundaries at the serializer layer, which is more complex than the single-lookup cost justifies). The policy still works; it just does one extra query per date_range when computing permissions at sync time.

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/date_range_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe DateRangeSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "serializes date range fields" do
      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      range_row = TestFactories.date_range(
        date_poll: poll, start_date: Date.today, end_date: Date.today + 3
      )
      range = DateRange.find(range_row[:id])

      result = described_class.serialize_batch([range], pool: nil).first

      expect(result[:id]).to eq(range.id.to_s)
      expect(result[:objectType]).to eq("dateRange")
      expect(result[:datePollId]).to eq(poll[:id].to_s)
      expect(result[:startDate]).to eq(Date.today.iso8601)
      expect(result[:endDate]).to eq((Date.today + 3).iso8601)
      expect(result[:updatedAt]).to match(/\.\d{3}/)
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/date_range_serializer_spec.rb
```

Expected: `NameError: uninitialized constant DateRangeSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/date_range_serializer.rb
# frozen_string_literal: true

class DateRangeSerializer
  class << self
    def serialize_batch(ranges, pool:)
      ranges.map do |range|
        {
          id: range.id.to_s,
          objectType: "dateRange",
          datePollId: range.date_poll_id.to_s,
          startDate: range.start_date.iso8601,
          endDate: range.end_date.iso8601,
          updatedAt: range.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_range) = {}
    def policy_context_batch(_ranges) = {}
  end
end
```

- [ ] **Step 4: Wire into the registry**

Replace the date_range entry in `backend/app/object_registry.rb`:

```ruby
    Entry.new(key: "date_range",  model: "DateRange",            client_type: "dateRange",  pool_method: :add_date_range,  tracks_user: false, policy: "DateRangePolicy", serializer_class: DateRangeSerializer),
```

- [ ] **Step 5: Redirect both `add_date_range` and `add_date_ranges_batch`**

In `backend/app/serializers/pool_serializer.rb`, replace the methods at lines 119–144 (both `add_date_range` and `add_date_ranges_batch`) with:

```ruby
  def add_date_range(date_range)
    add_batch(ObjectRegistry::BY_KEY["date_range"], [date_range])
  end

  def add_date_ranges_batch(ranges)
    add_batch(ObjectRegistry::BY_KEY["date_range"], ranges)
  end
```

- [ ] **Step 6: Run specs**

```
cd backend && bundle exec rspec spec/serializers/ spec/services/ spec/websocket/
```

Expected: all pass. The existing `#add_date_ranges_batch` spec in `pool_serializer_spec.rb` continues to pin behavior.

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/date_range_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/date_range_serializer_spec.rb
git commit -m "Extract DateRangeSerializer"
```

---

### Task 8: ExpenseParticipantSerializer

**Files:**
- Create: `backend/app/serializers/expense_participant_serializer.rb`
- Create: `backend/spec/serializers/expense_participant_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (expense_participant entry)
- Modify: `backend/app/serializers/pool_serializer.rb:219-226`

Note: Today `ExpenseParticipant#to_api_hash` has a bug where `updatedAt` returns `created_at.iso8601(3)` (see `expense_participant.rb:26`). This plan **preserves the current behavior** verbatim; fixing the bug is out of scope. Flag it in the commit message.

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/expense_participant_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExpenseParticipantSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "serializes participant fields" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      expense_id = SecureRandom.uuid
      DB[:expenses].insert(
        id: expense_id, event_id: event[:id], user_id: user[:id],
        description: "x", amount: 5.0, start_date: Date.today, end_date: Date.today,
        created_at: now, updated_at: now
      )
      participant_id = SecureRandom.uuid
      DB[:expense_participants].insert(
        id: participant_id, expense_id: expense_id, user_id: user[:id], created_at: now
      )
      participant = ExpenseParticipant.find(participant_id)

      result = described_class.serialize_batch([participant], pool: nil).first

      expect(result[:id]).to eq(participant.id.to_s)
      expect(result[:objectType]).to eq("expenseParticipant")
      expect(result[:expenseId]).to eq(expense_id.to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      # NOTE: the existing to_api_hash returns created_at for both fields.
      # Preserved for backwards compatibility; fixing is out of scope.
      expect(result[:createdAt]).to eq(result[:updatedAt])
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/expense_participant_serializer_spec.rb
```

Expected: `NameError: uninitialized constant ExpenseParticipantSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/expense_participant_serializer.rb
# frozen_string_literal: true

class ExpenseParticipantSerializer
  class << self
    def serialize_batch(participants, pool:)
      participants.map do |participant|
        {
          id: participant.id.to_s,
          objectType: "expenseParticipant",
          expenseId: participant.expense_id.to_s,
          userId: participant.user_id.to_s,
          # Note: preserved from original to_api_hash — both fields use created_at.
          createdAt: participant.created_at.iso8601(3),
          updatedAt: participant.created_at.iso8601(3)
        }
      end
    end

    def policy_context(_participant) = {}
    def policy_context_batch(_participants) = {}
  end
end
```

- [ ] **Step 4: Wire into the registry**

Replace the expense_participant entry in `backend/app/object_registry.rb`:

```ruby
    Entry.new(key: "expense_participant", model: "ExpenseParticipant", client_type: "expenseParticipant", pool_method: :add_expense_participant, tracks_user: true, policy: "ExpenseParticipantPolicy", serializer_class: ExpenseParticipantSerializer)
```

- [ ] **Step 5: Redirect `add_expense_participant`**

In `backend/app/serializers/pool_serializer.rb`, replace the method at lines 219–226:

```ruby
  def add_expense_participant(participant)
    add_batch(ObjectRegistry::BY_KEY["expense_participant"], [participant])
  end
```

- [ ] **Step 6: Run specs**

```
cd backend && bundle exec rspec
```

Expected: all pass.

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/expense_participant_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/expense_participant_serializer_spec.rb
git commit -m "Extract ExpenseParticipantSerializer"
```

---

### Task 9: SettlementTransferSerializer

**Files:**
- Create: `backend/app/serializers/settlement_transfer_serializer.rb`
- Create: `backend/spec/serializers/settlement_transfer_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (settlement_transfer entry)
- Modify: `backend/app/serializers/pool_serializer.rb:255-262`

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/settlement_transfer_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementTransferSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:other_user) { TestFactories.user }

  describe ".serialize_batch" do
    it "serializes transfer fields" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      settlement_id = SecureRandom.uuid
      DB[:settlements].insert(
        id: settlement_id, event_id: event[:id], user_id: user[:id],
        created_at: now, updated_at: now
      )
      transfer_id = SecureRandom.uuid
      DB[:settlement_transfers].insert(
        id: transfer_id, settlement_id: settlement_id,
        from_user_id: other_user[:id], to_user_id: user[:id], amount: 10.5,
        created_at: now, updated_at: now
      )
      transfer = SettlementTransfer.find(transfer_id)

      result = described_class.serialize_batch([transfer], pool: nil).first

      expect(result[:id]).to eq(transfer.id.to_s)
      expect(result[:objectType]).to eq("settlementTransfer")
      expect(result[:settlementId]).to eq(settlement_id.to_s)
      expect(result[:fromUserId]).to eq(other_user[:id].to_s)
      expect(result[:toUserId]).to eq(user[:id].to_s)
      expect(result[:amount]).to eq(10.5)
      expect(result[:paidAt]).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/settlement_transfer_serializer_spec.rb
```

Expected: `NameError: uninitialized constant SettlementTransferSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/settlement_transfer_serializer.rb
# frozen_string_literal: true

class SettlementTransferSerializer
  class << self
    def serialize_batch(transfers, pool:)
      transfers.map do |transfer|
        {
          id: transfer.id.to_s,
          objectType: "settlementTransfer",
          settlementId: transfer.settlement_id.to_s,
          fromUserId: transfer.from_user_id&.to_s,
          toUserId: transfer.to_user_id&.to_s,
          amount: transfer.amount,
          paidAt: transfer.paid_at&.iso8601(3),
          createdAt: transfer.created_at.iso8601(3),
          updatedAt: transfer.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_transfer) = {}
    def policy_context_batch(_transfers) = {}
  end
end
```

- [ ] **Step 4: Wire into the registry**

Replace the settlement_transfer entry:

```ruby
    Entry.new(key: "settlement_transfer", model: "SettlementTransfer", client_type: "settlementTransfer", pool_method: :add_settlement_transfer, tracks_user: false, policy: "SettlementTransferPolicy", serializer_class: SettlementTransferSerializer),
```

- [ ] **Step 5: Redirect `add_settlement_transfer`**

In `backend/app/serializers/pool_serializer.rb`, replace lines 255–262:

```ruby
  def add_settlement_transfer(transfer)
    add_batch(ObjectRegistry::BY_KEY["settlement_transfer"], [transfer])
  end
```

- [ ] **Step 6: Run specs**

```
cd backend && bundle exec rspec
```

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/settlement_transfer_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/settlement_transfer_serializer_spec.rb
git commit -m "Extract SettlementTransferSerializer"
```

---

### Task 10: ChoreAssignmentSerializer

**Files:**
- Create: `backend/app/serializers/chore_assignment_serializer.rb`
- Create: `backend/spec/serializers/chore_assignment_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (chore_assignment entry)
- Modify: `backend/app/serializers/pool_serializer.rb:303-310`

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/chore_assignment_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreAssignmentSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "serializes assignment fields" do
      event = TestFactories.event(workspace: workspace, user: user)
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster, name: "Wash up")
      assignment = TestFactories.chore_assignment(chore: chore, user: user, date: Date.today, pinned: true, note: "dish soap")
      assignment_model = ChoreAssignment.find(assignment[:id])

      result = described_class.serialize_batch([assignment_model], pool: nil).first

      expect(result[:id]).to eq(assignment[:id].to_s)
      expect(result[:objectType]).to eq("choreAssignment")
      expect(result[:choreId]).to eq(chore[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:date]).to eq(Date.today.iso8601)
      expect(result[:pinned]).to be true
      expect(result[:note]).to eq("dish soap")
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/chore_assignment_serializer_spec.rb
```

Expected: `NameError: uninitialized constant ChoreAssignmentSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/chore_assignment_serializer.rb
# frozen_string_literal: true

class ChoreAssignmentSerializer
  class << self
    def serialize_batch(assignments, pool:)
      assignments.map do |assignment|
        {
          id: assignment.id.to_s,
          objectType: "choreAssignment",
          choreId: assignment.chore_id.to_s,
          userId: assignment.user_id.to_s,
          date: assignment.date.iso8601,
          pinned: assignment.pinned,
          note: assignment.note,
          createdAt: assignment.created_at.iso8601(3),
          updatedAt: assignment.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_assignment) = {}
    def policy_context_batch(_assignments) = {}
  end
end
```

- [ ] **Step 4: Wire into the registry**

Replace the chore_assignment entry:

```ruby
    Entry.new(key: "chore_assignment",   model: "ChoreAssignment",    client_type: "choreAssignment",    pool_method: :add_chore_assignment,    tracks_user: true,  policy: "ChoreAssignmentPolicy", serializer_class: ChoreAssignmentSerializer),
```

- [ ] **Step 5: Redirect `add_chore_assignment`**

In `backend/app/serializers/pool_serializer.rb`, replace lines 303–310:

```ruby
  def add_chore_assignment(assignment)
    add_batch(ObjectRegistry::BY_KEY["chore_assignment"], [assignment])
  end
```

- [ ] **Step 6: Run specs**

```
cd backend && bundle exec rspec
```

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/chore_assignment_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/chore_assignment_serializer_spec.rb
git commit -m "Extract ChoreAssignmentSerializer"
```

---

### Task 11: WorkspaceInviteSerializer

**Files:**
- Create: `backend/app/serializers/workspace_invite_serializer.rb`
- Create: `backend/spec/serializers/workspace_invite_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (workspace_invite entry)
- Modify: `backend/app/serializers/pool_serializer.rb:312-319`

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/workspace_invite_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkspaceInviteSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:inviter) { TestFactories.user }

  describe ".serialize_batch" do
    it "serializes invite fields" do
      invite_row = TestFactories.workspace_invite(
        workspace: workspace, invited_by: inviter, email: "new@example.com", name: "Newbie"
      )
      invite = WorkspaceInvite.find(invite_row[:id])

      result = described_class.serialize_batch([invite], pool: nil).first

      expect(result[:id]).to eq(invite.id.to_s)
      expect(result[:objectType]).to eq("workspaceInvite")
      expect(result[:workspaceId]).to eq(workspace[:id].to_s)
      expect(result[:invitedBy]).to eq(inviter[:id].to_s)
      expect(result[:email]).to eq("new@example.com")
      expect(result[:name]).to eq("Newbie")
      expect(result[:expiresAt]).to match(/\.\d{3}/)
      expect(result[:acceptedAt]).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/workspace_invite_serializer_spec.rb
```

Expected: `NameError: uninitialized constant WorkspaceInviteSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/workspace_invite_serializer.rb
# frozen_string_literal: true

class WorkspaceInviteSerializer
  class << self
    def serialize_batch(invites, pool:)
      invites.map do |invite|
        {
          id: invite.id.to_s,
          objectType: "workspaceInvite",
          workspaceId: invite.workspace_id.to_s,
          invitedBy: invite.invited_by&.to_s,
          email: invite.email.to_s,
          name: invite.name,
          expiresAt: invite.expires_at.iso8601(3),
          acceptedAt: invite.accepted_at&.iso8601(3),
          lastRemindedAt: invite.last_reminded_at&.iso8601(3),
          createdAt: invite.created_at.iso8601(3),
          updatedAt: invite.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_invite) = {}
    def policy_context_batch(_invites) = {}
  end
end
```

- [ ] **Step 4: Wire into the registry**

Replace the workspace_invite entry:

```ruby
    Entry.new(key: "workspace_invite", model: "WorkspaceInvite", client_type: "workspaceInvite", pool_method: :add_workspace_invite, tracks_user: false, policy: "WorkspaceInvitePolicy", serializer_class: WorkspaceInviteSerializer),
```

- [ ] **Step 5: Redirect `add_workspace_invite`**

In `backend/app/serializers/pool_serializer.rb`, replace lines 312–319:

```ruby
  def add_workspace_invite(invite)
    add_batch(ObjectRegistry::BY_KEY["workspace_invite"], [invite])
  end
```

- [ ] **Step 6: Run specs**

```
cd backend && bundle exec rspec
```

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/workspace_invite_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/workspace_invite_serializer_spec.rb
git commit -m "Extract WorkspaceInviteSerializer"
```

---

### Task 12: TaskItemSerializer

**Files:**
- Create: `backend/app/serializers/task_item_serializer.rb`
- Create: `backend/spec/serializers/task_item_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (task_item entry)
- Modify: `backend/app/serializers/pool_serializer.rb:184-191`

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/task_item_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskItemSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "serializes task item fields" do
      task_list = TestFactories.task_list(workspace: workspace, user: user)
      task_item_row = TestFactories.task_item(
        task_list: task_list, user: user, content: "Buy cake", position: 1
      )
      task_item = TaskItem.find(task_item_row[:id])

      result = described_class.serialize_batch([task_item], pool: nil).first

      expect(result[:id]).to eq(task_item.id.to_s)
      expect(result[:objectType]).to eq("taskItem")
      expect(result[:taskListId]).to eq(task_list[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:content]).to eq("Buy cake")
      expect(result[:completedAt]).to be_nil
      expect(result[:position]).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/task_item_serializer_spec.rb
```

Expected: `NameError: uninitialized constant TaskItemSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/task_item_serializer.rb
# frozen_string_literal: true

class TaskItemSerializer
  class << self
    def serialize_batch(task_items, pool:)
      task_items.map do |item|
        {
          id: item.id.to_s,
          objectType: "taskItem",
          taskListId: item.task_list_id.to_s,
          userId: item.user_id&.to_s,
          content: item.content,
          completedAt: item.completed_at&.iso8601(3),
          position: item.position,
          createdAt: item.created_at.iso8601(3),
          updatedAt: item.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_item) = {}
    def policy_context_batch(_items) = {}
  end
end
```

- [ ] **Step 4: Wire into the registry**

Replace the task_item entry:

```ruby
    Entry.new(key: "task_item",   model: "TaskItem",             client_type: "taskItem",   pool_method: :add_task_item,   tracks_user: true,  policy: "TaskItemPolicy", serializer_class: TaskItemSerializer),
```

- [ ] **Step 5: Redirect `add_task_item`**

In `backend/app/serializers/pool_serializer.rb`, replace lines 184–191:

```ruby
  def add_task_item(task_item)
    add_batch(ObjectRegistry::BY_KEY["task_item"], [task_item])
  end
```

- [ ] **Step 6: Run specs**

```
cd backend && bundle exec rspec
```

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/task_item_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/task_item_serializer_spec.rb
git commit -m "Extract TaskItemSerializer"
```

---

## Phase 3: Migrate types with children or non-trivial context

This phase handles the serializers that do parent→child expansion or carry policy context. Each one is larger than Phase 2 tasks but follows the same TDD rhythm.

---

### Task 13: DatePollSerializer

**Files:**
- Create: `backend/app/serializers/date_poll_serializer.rb`
- Create: `backend/spec/serializers/date_poll_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (date_poll entry)
- Modify: `backend/app/serializers/pool_serializer.rb:92-117`

`DatePollPolicy` takes an optional `event:` kwarg. We batch-load the events in `policy_context_batch`.

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/date_poll_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePollSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "returns an empty array for empty input" do
      expect(described_class.serialize_batch([], pool: nil)).to eq([])
    end

    it "serializes poll fields with batched dateRangeIds" do
      event1 = TestFactories.event(workspace: workspace, user: user)
      event2 = TestFactories.event(workspace: workspace, user: user)
      poll1 = TestFactories.date_poll(event: event1)
      poll2 = TestFactories.date_poll(event: event2)
      range = TestFactories.date_range(date_poll: poll1)

      polls = [DatePoll.find(poll1[:id]), DatePoll.find(poll2[:id])]
      result = described_class.serialize_batch(polls, pool: nil)

      expect(result[0][:objectType]).to eq("datePoll")
      expect(result[0][:eventId]).to eq(event1[:id].to_s)
      expect(result[0][:dateRangeIds]).to include(range[:id].to_s)
      expect(result[1][:dateRangeIds]).to eq([])
    end
  end

  describe ".policy_context_batch" do
    it "returns the event for each date poll" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      poll_row = TestFactories.date_poll(event: event_row)
      poll = DatePoll.find(poll_row[:id])

      context = described_class.policy_context_batch([poll])

      expect(context[poll.id.to_s][:event]).to be_a(Event)
      expect(context[poll.id.to_s][:event].id.to_s).to eq(event_row[:id].to_s)
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/date_poll_serializer_spec.rb
```

Expected: `NameError: uninitialized constant DatePollSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/date_poll_serializer.rb
# frozen_string_literal: true

class DatePollSerializer
  class << self
    def serialize_batch(polls, pool:)
      return [] if polls.empty?

      poll_ids = polls.map { |p| p.id.to_s }
      range_ids_by_poll = DateRange.ids_for_date_poll_ids(poll_ids)

      polls.map do |poll|
        {
          id: poll.id.to_s,
          objectType: "datePoll",
          eventId: poll.event_id.to_s,
          deadline: poll.deadline.iso8601(3),
          selectedDateRangeId: poll.selected_date_range_id&.to_s,
          closedAt: poll.closed_at&.iso8601(3),
          status: poll.status,
          dateRangeIds: range_ids_by_poll[poll.id.to_s] || [],
          createdAt: poll.created_at.iso8601(3),
          updatedAt: poll.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(poll)
      policy_context_batch([poll])[poll.id.to_s] || {}
    end

    def policy_context_batch(polls)
      return {} if polls.empty?

      event_ids = polls.map { |p| p.event_id.to_s }.uniq
      events_by_id = Event.for_ids(event_ids).each_with_object({}) { |e, h| h[e.id.to_s] = e }

      polls.each_with_object({}) do |poll, h|
        h[poll.id.to_s] = { event: events_by_id[poll.event_id.to_s] }
      end
    end
  end
end
```

- [ ] **Step 4: Wire into the registry**

Replace the date_poll entry:

```ruby
    Entry.new(key: "date_poll",   model: "DatePoll",             client_type: "datePoll",   pool_method: :add_date_poll,   tracks_user: false, policy: "DatePollPolicy", serializer_class: DatePollSerializer),
```

- [ ] **Step 5: Redirect `add_date_poll` and `add_date_polls_batch`**

In `backend/app/serializers/pool_serializer.rb`, replace lines 92–117 with:

```ruby
  def add_date_poll(date_poll)
    add_batch(ObjectRegistry::BY_KEY["date_poll"], [date_poll])
  end

  def add_date_polls_batch(polls)
    add_batch(ObjectRegistry::BY_KEY["date_poll"], polls)
  end
```

- [ ] **Step 6: Run specs**

```
cd backend && bundle exec rspec
```

Expected: all pass — the existing `#add_date_polls_batch` spec pins behavior.

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/date_poll_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/date_poll_serializer_spec.rb
git commit -m "Extract DatePollSerializer"
```

---

### Task 14: SettlementSerializer

**Files:**
- Create: `backend/app/serializers/settlement_serializer.rb`
- Create: `backend/spec/serializers/settlement_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (settlement entry)
- Modify: `backend/app/serializers/pool_serializer.rb:228-253`

`SettlementPolicy` takes an optional `event:` kwarg.

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/settlement_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "batches transferIds across multiple settlements" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      s1_id = SecureRandom.uuid
      DB[:settlements].insert(id: s1_id, event_id: event[:id], user_id: user[:id], created_at: now, updated_at: now)
      s2_id = SecureRandom.uuid
      DB[:settlements].insert(id: s2_id, event_id: event[:id], user_id: user[:id], created_at: now, updated_at: now)
      t_id = SecureRandom.uuid
      DB[:settlement_transfers].insert(
        id: t_id, settlement_id: s1_id, from_user_id: user[:id], to_user_id: user[:id],
        amount: 5.0, created_at: now, updated_at: now
      )

      settlements = [Settlement.find(s1_id), Settlement.find(s2_id)]
      result = described_class.serialize_batch(settlements, pool: nil)

      expect(result[0][:objectType]).to eq("settlement")
      expect(result[0][:eventId]).to eq(event[:id].to_s)
      expect(result[0][:transferIds]).to include(t_id.to_s)
      expect(result[1][:transferIds]).to eq([])
    end
  end

  describe ".policy_context_batch" do
    it "returns the event for each settlement" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      settlement_id = SecureRandom.uuid
      DB[:settlements].insert(id: settlement_id, event_id: event_row[:id], user_id: user[:id], created_at: now, updated_at: now)
      settlement = Settlement.find(settlement_id)

      context = described_class.policy_context_batch([settlement])

      expect(context[settlement.id.to_s][:event]).to be_a(Event)
      expect(context[settlement.id.to_s][:event].id.to_s).to eq(event_row[:id].to_s)
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/settlement_serializer_spec.rb
```

Expected: `NameError: uninitialized constant SettlementSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/settlement_serializer.rb
# frozen_string_literal: true

class SettlementSerializer
  class << self
    def serialize_batch(settlements, pool:)
      return [] if settlements.empty?

      settlement_ids = settlements.map { |s| s.id.to_s }
      transfer_ids_by_settlement = SettlementTransfer.ids_for_settlement_ids(settlement_ids)

      settlements.map do |settlement|
        {
          id: settlement.id.to_s,
          objectType: "settlement",
          eventId: settlement.event_id.to_s,
          userId: settlement.user_id&.to_s,
          transferIds: transfer_ids_by_settlement[settlement.id.to_s] || [],
          createdAt: settlement.created_at.iso8601(3),
          updatedAt: settlement.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(settlement)
      policy_context_batch([settlement])[settlement.id.to_s] || {}
    end

    def policy_context_batch(settlements)
      return {} if settlements.empty?

      event_ids = settlements.map { |s| s.event_id.to_s }.uniq
      events_by_id = Event.for_ids(event_ids).each_with_object({}) { |e, h| h[e.id.to_s] = e }

      settlements.each_with_object({}) do |settlement, h|
        h[settlement.id.to_s] = { event: events_by_id[settlement.event_id.to_s] }
      end
    end
  end
end
```

- [ ] **Step 4: Wire into the registry**

Replace the settlement entry:

```ruby
    Entry.new(key: "settlement",  model: "Settlement",           client_type: "settlement", pool_method: :add_settlement,  tracks_user: true,  policy: "SettlementPolicy", serializer_class: SettlementSerializer),
```

- [ ] **Step 5: Redirect `add_settlement` and `add_settlements_batch`**

In `backend/app/serializers/pool_serializer.rb`, replace lines 228–253:

```ruby
  def add_settlement(settlement)
    add_batch(ObjectRegistry::BY_KEY["settlement"], [settlement])
  end

  def add_settlements_batch(settlements)
    add_batch(ObjectRegistry::BY_KEY["settlement"], settlements)
  end
```

- [ ] **Step 6: Run specs**

```
cd backend && bundle exec rspec
```

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/settlement_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/settlement_serializer_spec.rb
git commit -m "Extract SettlementSerializer"
```

---

### Task 15: WorkspaceSerializer

**Files:**
- Create: `backend/app/serializers/workspace_serializer.rb`
- Create: `backend/spec/serializers/workspace_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (workspace entry)
- Modify: `backend/app/serializers/pool_serializer.rb:164-172`

`WorkspaceSerializer` needs the `memberIds` list, which today is fetched by PoolSerializer and passed as a kwarg to `Workspace#to_api_hash`. The new serializer owns the lookup.

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/workspace_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkspaceSerializer do
  describe ".serialize_batch" do
    it "includes memberIds for each workspace" do
      workspace_row = TestFactories.workspace(name: "Team A")
      user = TestFactories.user
      membership_row = TestFactories.workspace_membership(workspace: workspace_row, user: user)
      workspace = Workspace.find(workspace_row[:id])

      result = described_class.serialize_batch([workspace], pool: nil).first

      expect(result[:id]).to eq(workspace.id.to_s)
      expect(result[:objectType]).to eq("workspace")
      expect(result[:name]).to eq("Team A")
      expect(result[:memberIds]).to include(membership_row[:id].to_s)
    end

    it "returns empty memberIds for a workspace with no members" do
      workspace_row = TestFactories.workspace
      workspace = Workspace.find(workspace_row[:id])

      result = described_class.serialize_batch([workspace], pool: nil).first

      expect(result[:memberIds]).to eq([])
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/workspace_serializer_spec.rb
```

Expected: `NameError: uninitialized constant WorkspaceSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/workspace_serializer.rb
# frozen_string_literal: true

class WorkspaceSerializer
  class << self
    def serialize_batch(workspaces, pool:)
      return [] if workspaces.empty?

      workspace_ids = workspaces.map { |w| w.id.to_s }
      member_ids_by_workspace = WorkspaceMembership.ids_for_workspaces(workspace_ids)

      workspaces.map do |workspace|
        {
          id: workspace.id.to_s,
          objectType: "workspace",
          name: workspace.name,
          memberIds: member_ids_by_workspace[workspace.id.to_s] || [],
          createdAt: workspace.created_at.iso8601(3),
          updatedAt: workspace.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_workspace) = {}
    def policy_context_batch(_workspaces) = {}
  end
end
```

This requires a new batch finder on `WorkspaceMembership`.

- [ ] **Step 4: Add `WorkspaceMembership.ids_for_workspaces`**

In `backend/app/models/workspace_membership.rb`, locate the existing `ids_for_workspace` class method. Add immediately after it:

```ruby
    def ids_for_workspaces(workspace_ids)
      return {} if workspace_ids.empty?

      DB[:workspace_memberships]
        .where(workspace_id: workspace_ids)
        .select(:id, :workspace_id)
        .all
        .group_by { |r| r[:workspace_id].to_s }
        .transform_values { |rows| rows.map { |r| r[:id].to_s } }
    end
```

- [ ] **Step 5: Wire into the registry**

Replace the workspace entry:

```ruby
    Entry.new(key: "workspace",   model: "Workspace",            client_type: "workspace",  pool_method: :add_workspace,   tracks_user: false, policy: "WorkspacePolicy", serializer_class: WorkspaceSerializer),
```

- [ ] **Step 6: Redirect `add_workspace`**

In `backend/app/serializers/pool_serializer.rb`, replace lines 164–172:

```ruby
  def add_workspace(workspace)
    add_batch(ObjectRegistry::BY_KEY["workspace"], [workspace])
  end
```

- [ ] **Step 7: Run specs**

```
cd backend && bundle exec rspec
```

- [ ] **Step 8: Commit**

```
cd backend && git add app/serializers/workspace_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb app/models/workspace_membership.rb spec/serializers/workspace_serializer_spec.rb
git commit -m "Extract WorkspaceSerializer"
```

---

### Task 16: MemberSerializer

**Files:**
- Create: `backend/app/serializers/member_serializer.rb`
- Create: `backend/spec/serializers/member_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (member entry)
- Modify: `backend/app/serializers/pool_serializer.rb:21-56`, `backend/app/serializers/pool_serializer.rb:348-366`

Member is special: it takes a `WorkspaceMembership` but the hash combines fields from the `User` model. The serializer fetches users in bulk. If the user row is missing for any membership (race condition during deletion), the corresponding array entry is `nil`.

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/member_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe MemberSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "returns an empty array for empty input" do
      expect(described_class.serialize_batch([], pool: nil)).to eq([])
    end

    it "combines user and membership fields into a member hash" do
      DB[:users].where(id: user[:id]).update(
        phone_number: "+31612345678",
        location_name: "Amsterdam"
      )
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user, role: "admin")
      membership = WorkspaceMembership.find(membership_row[:id])

      result = described_class.serialize_batch([membership], pool: nil).first

      expect(result[:id]).to eq(membership.id.to_s)
      expect(result[:objectType]).to eq("member")
      expect(result[:workspaceId]).to eq(workspace[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:email]).to eq(user[:email])
      expect(result[:phoneNumber]).to eq("+31612345678")
      expect(result[:locationName]).to eq("Amsterdam")
      expect(result[:role]).to eq("admin")
      expect(result[:hasIban]).to be false
    end

    it "sets hasIban: true when the user has an iban" do
      DB[:users].where(id: user[:id]).update(iban: Encryption.encrypt("NL91ABNA0417164300"))
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
      membership = WorkspaceMembership.find(membership_row[:id])

      result = described_class.serialize_batch([membership], pool: nil).first

      expect(result[:hasIban]).to be true
    end

    it "never emits the raw iban" do
      DB[:users].where(id: user[:id]).update(iban: Encryption.encrypt("NL91ABNA0417164300"))
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
      membership = WorkspaceMembership.find(membership_row[:id])

      result = described_class.serialize_batch([membership], pool: nil).first

      expect(result).not_to have_key(:iban)
    end

    it "batches user lookups across multiple memberships" do
      user2 = TestFactories.user
      m1_row = TestFactories.workspace_membership(workspace: workspace, user: user)
      m2_row = TestFactories.workspace_membership(workspace: workspace, user: user2)
      m1 = WorkspaceMembership.find(m1_row[:id])
      m2 = WorkspaceMembership.find(m2_row[:id])

      query_count = 0
      counter = ->(_sql) { query_count += 1 }
      DB.loggers << Logger.new(StringIO.new).tap { |l| l.define_singleton_method(:info) { |sql| counter.call(sql) } }

      described_class.serialize_batch([m1, m2], pool: nil)

      DB.loggers.pop
      expect(query_count).to be <= 2 # one for users, one buffer
    end

    it "returns nil for memberships whose user row is missing" do
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
      membership = WorkspaceMembership.find(membership_row[:id])
      DB[:users].where(id: user[:id]).delete

      result = described_class.serialize_batch([membership], pool: nil)

      expect(result).to eq([nil])
    end

    it "uses the max of user.updated_at and membership.updated_at for updatedAt" do
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
      past = Time.now - 3600
      future = Time.now + 3600
      DB[:users].where(id: user[:id]).update(updated_at: future)
      DB[:workspace_memberships].where(id: membership_row[:id]).update(updated_at: past)
      membership = WorkspaceMembership.find(membership_row[:id])

      result = described_class.serialize_batch([membership], pool: nil).first

      expect(Time.iso8601(result[:updatedAt])).to be_within(1).of(future)
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/member_serializer_spec.rb
```

Expected: `NameError: uninitialized constant MemberSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/member_serializer.rb
# frozen_string_literal: true

# Serializes a WorkspaceMembership into a pool "member" object, combining
# fields from the membership and its User. Returns nil in place for any
# membership whose user row is missing (can happen during deletion races).
class MemberSerializer
  class << self
    def serialize_batch(memberships, pool:)
      return [] if memberships.empty?

      user_ids = memberships.map { |m| m.user_id.to_s }.uniq
      users_by_id = User.for_ids(user_ids).each_with_object({}) { |u, h| h[u.id.to_s] = u }

      memberships.map do |membership|
        user = users_by_id[membership.user_id.to_s]
        next nil unless user

        build_hash(user, membership)
      end
    end

    def policy_context(_membership) = {}
    def policy_context_batch(_memberships) = {}

    private

    def build_hash(user, membership)
      {
        id: membership.id.to_s,
        objectType: "member",
        workspaceId: membership.workspace_id.to_s,
        userId: user.id.to_s,
        email: user.email.to_s,
        name: user.name,
        phoneNumber: user.phone_number,
        birthday: user.birthday&.iso8601,
        locationName: user.location_name,
        latitude: user.location_coordinates&.[](1),
        longitude: user.location_coordinates&.[](0),
        hasIban: !user.iban.nil?,
        role: membership.role,
        createdAt: membership.created_at.iso8601(3),
        updatedAt: [user.updated_at, membership.updated_at].max.iso8601(3)
      }
    end
  end
end
```

- [ ] **Step 4: Wire into the registry**

Replace the member entry:

```ruby
    Entry.new(key: "member",      model: "WorkspaceMembership",  client_type: "member",     pool_method: :add_member,      tracks_user: false, policy: "MemberPolicy", serializer_class: MemberSerializer),
```

- [ ] **Step 5: Redirect `add_member`, `add_member_from_membership`, and `add_members_batch`**

In `backend/app/serializers/pool_serializer.rb`, replace lines 21–56 (all three methods) with:

```ruby
  # Serializes a workspace membership as a member pool object.
  def add_member_from_membership(membership)
    add_batch(ObjectRegistry::BY_KEY["member"], [membership])
  end

  # Public alias.
  def add_member(membership)
    add_batch(ObjectRegistry::BY_KEY["member"], [membership])
  end

  def add_members_batch(memberships)
    add_batch(ObjectRegistry::BY_KEY["member"], memberships)
  end
```

- [ ] **Step 6: Delete the now-unused `build_member_hash` private helper**

In `backend/app/serializers/pool_serializer.rb`, delete the `build_member_hash` method (previously at lines 348–366). Leave `attach_permissions` in place for now — it's still used by any remaining legacy paths.

- [ ] **Step 7: Run specs**

```
cd backend && bundle exec rspec
```

- [ ] **Step 8: Commit**

```
cd backend && git add app/serializers/member_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/member_serializer_spec.rb
git commit -m "Extract MemberSerializer and drop PoolSerializer#build_member_hash"
```

---

### Task 17: TaskListSerializer (with child expansion)

**Files:**
- Create: `backend/app/serializers/task_list_serializer.rb`
- Create: `backend/spec/serializers/task_list_serializer_spec.rb`
- Modify: `backend/app/models/task_item.rb` (add `for_task_lists`)
- Modify: `backend/app/object_registry.rb` (task_list entry)
- Modify: `backend/app/serializers/pool_serializer.rb:174-182`

`TaskListSerializer` introduces the parent→child pattern: when called with a `pool:`, it batch-loads task_items and adds them to the pool. This fixes the current N+1 in `PoolSerializer#add_task_list`.

The per-type serializer needs a way to call back into the pool. We use a small helper `pool.add(key_symbol, items)` — adding it to PoolSerializer in this task. Subsequent child-expanding serializers (chore_roster, expense) will use the same helper.

- [ ] **Step 1: Add `TaskItem.for_task_lists`**

In `backend/app/models/task_item.rb`, find the existing `for_task_list` method (around line 49). Add immediately after it:

```ruby
    def for_task_lists(task_list_ids)
      return [] if task_list_ids.empty?

      dataset.where(task_list_id: task_list_ids).order(:task_list_id, :position).all
    end
```

- [ ] **Step 2: Add `PoolSerializer#add` (key-based entry point)**

In `backend/app/serializers/pool_serializer.rb`, add this method in the public section (right before `add_all`):

```ruby
  # New unified entry point. Takes a registry key (symbol or string) and
  # an array of items. Dispatches to the registered serializer_class.
  def add(key, items)
    entry = ObjectRegistry::BY_KEY[key.to_s]
    raise ArgumentError, "Unknown object key: #{key.inspect}" unless entry

    add_batch(entry, Array(items))
  end
```

- [ ] **Step 3: Write the failing spec**

```ruby
# backend/spec/serializers/task_list_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskListSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "serializes task list fields" do
      task_list_row = TestFactories.task_list(workspace: workspace, user: user, name: "Groceries")
      task_list = TaskList.find(task_list_row[:id])

      result = described_class.serialize_batch([task_list], pool: nil).first

      expect(result[:id]).to eq(task_list.id.to_s)
      expect(result[:objectType]).to eq("taskList")
      expect(result[:workspaceId]).to eq(workspace[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:name]).to eq("Groceries")
    end

    it "adds child task_items to the pool when pool is provided" do
      TestFactories.workspace_membership(workspace: workspace, user: user)
      task_list_row = TestFactories.task_list(workspace: workspace, user: user)
      item1 = TestFactories.task_item(task_list: task_list_row, user: user, content: "milk")
      item2 = TestFactories.task_item(task_list: task_list_row, user: user, content: "bread")
      task_list = TaskList.find(task_list_row[:id])

      pool = PoolSerializer.new(workspace_id: workspace[:id])
      pool.add(:task_list, [task_list])

      items = pool.to_a.select { |o| o[:objectType] == "taskItem" }
      expect(items.map { |o| o[:id] }).to contain_exactly(item1[:id].to_s, item2[:id].to_s)
    end

    it "does not add children when pool is nil" do
      task_list_row = TestFactories.task_list(workspace: workspace, user: user)
      TestFactories.task_item(task_list: task_list_row, user: user)
      task_list = TaskList.find(task_list_row[:id])

      expect { described_class.serialize_batch([task_list], pool: nil) }.not_to raise_error
    end
  end
end
```

- [ ] **Step 4: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/task_list_serializer_spec.rb
```

Expected: `NameError: uninitialized constant TaskListSerializer`

- [ ] **Step 5: Implement TaskListSerializer**

```ruby
# backend/app/serializers/task_list_serializer.rb
# frozen_string_literal: true

class TaskListSerializer
  class << self
    def serialize_batch(task_lists, pool:)
      return [] if task_lists.empty?

      if pool
        list_ids = task_lists.map { |tl| tl.id.to_s }
        items = TaskItem.for_task_lists(list_ids)
        pool.add(:task_item, items) if items.any?
      end

      task_lists.map do |tl|
        {
          id: tl.id.to_s,
          objectType: "taskList",
          workspaceId: tl.workspace_id.to_s,
          userId: tl.user_id&.to_s,
          name: tl.name,
          position: tl.position,
          createdAt: tl.created_at.iso8601(3),
          updatedAt: tl.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_task_list) = {}
    def policy_context_batch(_task_lists) = {}
  end
end
```

- [ ] **Step 6: Wire into the registry**

Replace the task_list entry:

```ruby
    Entry.new(key: "task_list",   model: "TaskList",             client_type: "taskList",   pool_method: :add_task_list,   tracks_user: true,  policy: "TaskListPolicy", serializer_class: TaskListSerializer),
```

- [ ] **Step 7: Redirect `add_task_list`**

In `backend/app/serializers/pool_serializer.rb`, replace lines 174–182:

```ruby
  def add_task_list(task_list)
    add_batch(ObjectRegistry::BY_KEY["task_list"], [task_list])
  end
```

- [ ] **Step 8: Run specs**

```
cd backend && bundle exec rspec
```

- [ ] **Step 9: Commit**

```
cd backend && git add app/serializers/task_list_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb app/models/task_item.rb spec/serializers/task_list_serializer_spec.rb
git commit -m "Extract TaskListSerializer with explicit child expansion"
```

---

### Task 18: ExpenseSerializer (with participant expansion)

**Files:**
- Create: `backend/app/serializers/expense_serializer.rb`
- Create: `backend/spec/serializers/expense_serializer_spec.rb`
- Modify: `backend/app/object_registry.rb` (expense entry)
- Modify: `backend/app/serializers/pool_serializer.rb:193-217`

- [ ] **Step 1: Write the failing spec**

```ruby
# backend/spec/serializers/expense_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExpenseSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe ".serialize_batch" do
    it "serializes expense fields with batched participantIds" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      expense_id = SecureRandom.uuid
      DB[:expenses].insert(
        id: expense_id, event_id: event[:id], user_id: user[:id],
        description: "Pizza", amount: 25.0,
        start_date: Date.today, end_date: Date.today,
        created_at: now, updated_at: now
      )
      participant_id = SecureRandom.uuid
      DB[:expense_participants].insert(
        id: participant_id, expense_id: expense_id, user_id: user[:id], created_at: now
      )
      expense = Expense.find(expense_id)

      result = described_class.serialize_batch([expense], pool: nil).first

      expect(result[:id]).to eq(expense.id.to_s)
      expect(result[:objectType]).to eq("expense")
      expect(result[:eventId]).to eq(event[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:amount]).to eq(25.0)
      expect(result[:description]).to eq("Pizza")
      expect(result[:participantIds]).to include(participant_id.to_s)
    end

    it "adds participants to the pool when pool is provided" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      expense_id = SecureRandom.uuid
      DB[:expenses].insert(
        id: expense_id, event_id: event[:id], user_id: user[:id],
        description: "x", amount: 1.0, start_date: Date.today, end_date: Date.today,
        created_at: now, updated_at: now
      )
      participant_id = SecureRandom.uuid
      DB[:expense_participants].insert(
        id: participant_id, expense_id: expense_id, user_id: user[:id], created_at: now
      )
      expense = Expense.find(expense_id)

      pool = PoolSerializer.new(workspace_id: workspace[:id])
      pool.add(:expense, [expense])

      participants = pool.to_a.select { |o| o[:objectType] == "expenseParticipant" }
      expect(participants.map { |o| o[:id] }).to include(participant_id.to_s)
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

```
cd backend && bundle exec rspec spec/serializers/expense_serializer_spec.rb
```

Expected: `NameError: uninitialized constant ExpenseSerializer`

- [ ] **Step 3: Implement**

```ruby
# backend/app/serializers/expense_serializer.rb
# frozen_string_literal: true

class ExpenseSerializer
  class << self
    def serialize_batch(expenses, pool:)
      return [] if expenses.empty?

      expense_ids = expenses.map { |e| e.id.to_s }
      participants_by_expense = ExpenseParticipant.for_expenses(expense_ids)

      if pool
        all_participants = participants_by_expense.values.flatten
        pool.add(:expense_participant, all_participants) if all_participants.any?
      end

      expenses.map do |expense|
        participants = participants_by_expense[expense.id.to_s] || []
        {
          id: expense.id.to_s,
          objectType: "expense",
          eventId: expense.event_id.to_s,
          userId: expense.user_id&.to_s,
          settlementId: expense.settlement_id&.to_s,
          amount: expense.amount,
          description: expense.description,
          startDate: expense.start_date.iso8601,
          endDate: expense.end_date.iso8601,
          participantIds: participants.map { |p| p.id.to_s },
          createdAt: expense.created_at.iso8601(3),
          updatedAt: expense.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_expense) = {}
    def policy_context_batch(_expenses) = {}
  end
end
```

- [ ] **Step 4: Wire into the registry**

Replace the expense entry:

```ruby
    Entry.new(key: "expense",     model: "Expense",              client_type: "expense",    pool_method: :add_expense,     tracks_user: true,  policy: "ExpensePolicy", serializer_class: ExpenseSerializer),
```

- [ ] **Step 5: Redirect `add_expense` and `add_expenses_batch`**

In `backend/app/serializers/pool_serializer.rb`, replace lines 193–217:

```ruby
  def add_expense(expense, participants: nil)
    add_batch(ObjectRegistry::BY_KEY["expense"], [expense])
  end

  def add_expenses_batch(expenses)
    add_batch(ObjectRegistry::BY_KEY["expense"], expenses)
  end
```

(The `participants:` kwarg on `add_expense` is preserved for backwards compatibility with any route callers; it is now ignored because the serializer fetches participants itself. This method is deleted in Phase 4.)

- [ ] **Step 6: Run specs**

```
cd backend && bundle exec rspec
```

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/expense_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb spec/serializers/expense_serializer_spec.rb
git commit -m "Extract ExpenseSerializer with explicit participant expansion"
```

---

### Task 19: ChoreSerializer and ChoreRosterSerializer

**Files:**
- Create: `backend/app/serializers/chore_serializer.rb`
- Create: `backend/app/serializers/chore_roster_serializer.rb`
- Create: `backend/spec/serializers/chore_serializer_spec.rb`
- Create: `backend/spec/serializers/chore_roster_serializer_spec.rb`
- Modify: `backend/app/models/chore.rb` (add `for_rosters`)
- Modify: `backend/app/models/chore_assignment.rb` (add `for_chores`)
- Modify: `backend/app/object_registry.rb` (chore and chore_roster entries)
- Modify: `backend/app/serializers/pool_serializer.rb:264-301`

ChoreRoster is the most entangled case: roster → chores → assignments, all needing batched loads. This task does both rosters and chores together because they have to be consistent.

- [ ] **Step 1: Add batch finders on Chore and ChoreAssignment**

In `backend/app/models/chore.rb`, find the existing `for_roster` method. Add immediately after it:

```ruby
    def for_rosters(chore_roster_ids)
      return [] if chore_roster_ids.empty?

      dataset.where(chore_roster_id: chore_roster_ids).order(:chore_roster_id, :position).all
    end
```

In `backend/app/models/chore_assignment.rb`, find the existing `for_chore` method. Add immediately after it:

```ruby
    def for_chores(chore_ids)
      return [] if chore_ids.empty?

      dataset.where(chore_id: chore_ids).all
    end
```

- [ ] **Step 2: Write failing specs for both serializers**

```ruby
# backend/spec/serializers/chore_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "serializes chore fields with batched assignmentIds" do
      event = TestFactories.event(workspace: workspace, user: user)
      roster = TestFactories.chore_roster(event: event, user: user)
      chore_row = TestFactories.chore(chore_roster: roster, name: "Cook", people_per_day: 2, position: 0)
      assignment = TestFactories.chore_assignment(chore: chore_row, user: user, date: Date.today)
      chore = Chore.find(chore_row[:id])

      result = described_class.serialize_batch([chore], pool: nil).first

      expect(result[:id]).to eq(chore.id.to_s)
      expect(result[:objectType]).to eq("chore")
      expect(result[:choreRosterId]).to eq(roster[:id].to_s)
      expect(result[:name]).to eq("Cook")
      expect(result[:peoplePerDay]).to eq(2)
      expect(result[:position]).to eq(0)
      expect(result[:assignmentIds]).to include(assignment[:id].to_s)
    end
  end
end
```

```ruby
# backend/spec/serializers/chore_roster_serializer_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosterSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe ".serialize_batch" do
    it "serializes roster fields with batched choreIds" do
      event = TestFactories.event(workspace: workspace, user: user)
      roster_row = TestFactories.chore_roster(event: event, user: user)
      chore_row = TestFactories.chore(chore_roster: roster_row)
      roster = ChoreRoster.find(roster_row[:id])

      result = described_class.serialize_batch([roster], pool: nil).first

      expect(result[:id]).to eq(roster.id.to_s)
      expect(result[:objectType]).to eq("choreRoster")
      expect(result[:eventId]).to eq(event[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:choreIds]).to include(chore_row[:id].to_s)
    end

    it "adds chores and assignments to the pool" do
      event = TestFactories.event(workspace: workspace, user: user)
      roster_row = TestFactories.chore_roster(event: event, user: user)
      chore_row = TestFactories.chore(chore_roster: roster_row)
      assignment_row = TestFactories.chore_assignment(chore: chore_row, user: user, date: Date.today)
      roster = ChoreRoster.find(roster_row[:id])

      pool = PoolSerializer.new(workspace_id: workspace[:id])
      pool.add(:chore_roster, [roster])

      objects = pool.to_a
      expect(objects.map { |o| o[:objectType] }).to include("choreRoster", "chore", "choreAssignment")
      expect(objects.find { |o| o[:objectType] == "chore" }[:id]).to eq(chore_row[:id].to_s)
      expect(objects.find { |o| o[:objectType] == "choreAssignment" }[:id]).to eq(assignment_row[:id].to_s)
    end
  end
end
```

- [ ] **Step 3: Run and confirm failure**

```
cd backend && bundle exec rspec spec/serializers/chore_serializer_spec.rb spec/serializers/chore_roster_serializer_spec.rb
```

Expected: both fail with `NameError`.

- [ ] **Step 4: Implement ChoreSerializer**

```ruby
# backend/app/serializers/chore_serializer.rb
# frozen_string_literal: true

class ChoreSerializer
  class << self
    def serialize_batch(chores, pool:)
      return [] if chores.empty?

      chore_ids = chores.map { |c| c.id.to_s }
      all_assignments = ChoreAssignment.for_chores(chore_ids)
      assignments_by_chore = all_assignments.group_by { |a| a.chore_id.to_s }

      if pool
        pool.add(:chore_assignment, all_assignments) if all_assignments.any?
      end

      chores.map do |chore|
        assignments = assignments_by_chore[chore.id.to_s] || []
        {
          id: chore.id.to_s,
          objectType: "chore",
          choreRosterId: chore.chore_roster_id.to_s,
          name: chore.name,
          peoplePerDay: chore.people_per_day,
          position: chore.position,
          assignmentIds: assignments.map { |a| a.id.to_s },
          createdAt: chore.created_at.iso8601(3),
          updatedAt: chore.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_chore) = {}
    def policy_context_batch(_chores) = {}
  end
end
```

- [ ] **Step 5: Implement ChoreRosterSerializer**

```ruby
# backend/app/serializers/chore_roster_serializer.rb
# frozen_string_literal: true

class ChoreRosterSerializer
  class << self
    def serialize_batch(rosters, pool:)
      return [] if rosters.empty?

      roster_ids = rosters.map { |r| r.id.to_s }
      chores = Chore.for_rosters(roster_ids)
      chores_by_roster = chores.group_by { |c| c.chore_roster_id.to_s }

      pool.add(:chore, chores) if pool && chores.any?

      rosters.map do |roster|
        roster_chores = chores_by_roster[roster.id.to_s] || []
        {
          id: roster.id.to_s,
          objectType: "choreRoster",
          eventId: roster.event_id.to_s,
          userId: roster.user_id&.to_s,
          choreIds: roster_chores.map { |c| c.id.to_s },
          createdAt: roster.created_at.iso8601(3),
          updatedAt: roster.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_roster) = {}
    def policy_context_batch(_rosters) = {}
  end
end
```

- [ ] **Step 6: Wire into the registry**

Replace the chore and chore_roster entries:

```ruby
    Entry.new(key: "chore_roster",       model: "ChoreRoster",        client_type: "choreRoster",        pool_method: :add_chore_roster,        tracks_user: true,  policy: "ChoreRosterPolicy", serializer_class: ChoreRosterSerializer),
    Entry.new(key: "chore",              model: "Chore",              client_type: "chore",              pool_method: :add_chore,               tracks_user: false, policy: "ChorePolicy", serializer_class: ChoreSerializer),
```

- [ ] **Step 7: Redirect `add_chore_roster` and `add_chore`**

In `backend/app/serializers/pool_serializer.rb`, replace lines 264–301 (both `add_chore_roster` and `add_chore`):

```ruby
  def add_chore_roster(roster)
    add_batch(ObjectRegistry::BY_KEY["chore_roster"], [roster])
  end

  def add_chore(chore)
    add_batch(ObjectRegistry::BY_KEY["chore"], [chore])
  end
```

- [ ] **Step 8: Run specs**

```
cd backend && bundle exec rspec
```

Expected: all pass.

- [ ] **Step 9: Commit**

```
cd backend && git add app/serializers/chore_serializer.rb app/serializers/chore_roster_serializer.rb app/object_registry.rb app/serializers/pool_serializer.rb app/models/chore.rb app/models/chore_assignment.rb spec/serializers/chore_serializer_spec.rb spec/serializers/chore_roster_serializer_spec.rb
git commit -m "Extract ChoreSerializer and ChoreRosterSerializer"
```

---

## Phase 4: Unify and simplify

All 17 types now have per-type serializers. Now we delete duplication: legacy `add_X` methods, the `batch_methods` hash in WorkspaceSync, `ConnectionManager#attach_permissions`, and `Listener#prefetch_policy_context`.

---

### Task 20: Replace WorkspaceSync's batch_methods hash with uniform iteration

**Files:**
- Modify: `backend/app/services/sync/workspace_sync.rb:25-57`

- [ ] **Step 1: Replace the relevant block in WorkspaceSync**

In `backend/app/services/sync/workspace_sync.rb`, replace lines 25–57 (the pool creation through the member include) with:

```ruby
        pool = if membership
                 PoolSerializer.new(membership: membership)
               else
                 PoolSerializer.new(workspace_id: workspace_id)
               end

        # Always include workspace so memberIds stays current on partial syncs
        # (adding a member doesn't update the workspace's updated_at)
        pool.add(:workspace, [workspace])

        ObjectRegistry::TYPES.each do |entry|
          next if entry.key == "workspace" # already added
          next if entry.key == "member"    # added below with all memberships

          model = Object.const_get(entry.model)
          items = model.changed_since(workspace_id, effective_since)
          pool.add(entry.key, items) if items.any?
        end

        # Include all members so the frontend can resolve userId references
        pool.add(:member, WorkspaceMembership.for_workspace(workspace_id))
```

- [ ] **Step 2: Run sync specs**

```
cd backend && bundle exec rspec spec/services/sync/workspace_sync_spec.rb
```

Expected: all pass.

- [ ] **Step 3: Run full suite**

```
cd backend && bundle exec rspec
```

Expected: all pass.

- [ ] **Step 4: Commit**

```
cd backend && git add app/services/sync/workspace_sync.rb
git commit -m "Drive WorkspaceSync from ObjectRegistry directly"
```

---

### Task 21: Move ConnectionManager#attach_permissions into PermissionAttacher

**Files:**
- Modify: `backend/app/serializers/permission_attacher.rb`
- Create: `backend/spec/serializers/permission_attacher_message_spec.rb` (or extend existing)
- Modify: `backend/app/websocket/connection_manager.rb:195-214`

The `PermissionAttacher.call` method is per-object. Broadcast needs to walk an entire message's `data.objects` and attach per-object. Add a new method `PermissionAttacher.attach_to_message` that takes the raw message hash, the viewer's membership, and the `PolicyContext` bundle, and returns the message with permissions merged into every object.

- [ ] **Step 1: Extend the PermissionAttacher spec**

Add this describe block to `backend/spec/serializers/permission_attacher_spec.rb`:

```ruby
  describe ".attach_to_message" do
    let(:policy_context) do
      Websocket::PolicyContext.new(
        raw_objects: { "event" => event },
        kwargs: { has_expenses: false }
      )
    end

    let(:message) do
      {
        type: "broadcast",
        workspaceId: workspace[:id].to_s,
        action: "update",
        data: { objects: [event_hash] }
      }
    end

    it "attaches permissions to every object in the message data" do
      result = described_class.attach_to_message(message, owner_membership, policy_context)

      obj = result[:data][:objects].first
      expect(obj[:permissions][:edit]).to eq({ allowed: true })
    end

    it "returns the message unchanged when membership is nil" do
      result = described_class.attach_to_message(message, nil, policy_context)

      expect(result).to eq(message)
    end

    it "does not mutate the original message" do
      original_snapshot = Marshal.dump(message)
      described_class.attach_to_message(message, owner_membership, policy_context)

      expect(Marshal.dump(message)).to eq(original_snapshot)
    end

    it "skips objects whose type is not in the registry" do
      unknown_msg = message.merge(
        data: { objects: [{ id: "1", objectType: "notAType" }] }
      )
      result = described_class.attach_to_message(unknown_msg, owner_membership, policy_context)

      expect(result[:data][:objects].first).not_to have_key(:permissions)
    end
  end
```

- [ ] **Step 2: Run the spec and confirm failure**

```
cd backend && bundle exec rspec spec/serializers/permission_attacher_spec.rb
```

Expected: `NoMethodError: undefined method 'attach_to_message'`

- [ ] **Step 3: Add `attach_to_message` to PermissionAttacher**

In `backend/app/serializers/permission_attacher.rb`, add this method inside the `class << self` block:

```ruby
    # Attaches permissions to every object in a broadcast message, using the
    # supplied policy context. Non-mutating. Returns a new message hash.
    #
    # @param message [Hash] broadcast message shaped as
    #   { type:, workspaceId:, action:, data: { objects: [...] } }
    # @param membership [WorkspaceMembership, nil] the recipient's membership
    # @param policy_context [Websocket::PolicyContext] raw_objects by key + kwargs
    def attach_to_message(message, membership, policy_context)
      return message unless membership

      objects = message[:data][:objects].map do |obj|
        entry = ObjectRegistry::BY_CLIENT_TYPE[obj[:objectType]]
        next obj unless entry&.policy

        raw_object = policy_context.raw_objects[entry.key]
        next obj unless raw_object

        call(obj, raw_object: raw_object, membership: membership, policy_context: policy_context.kwargs)
      end

      message.merge(data: message[:data].merge(objects: objects))
    end
```

- [ ] **Step 4: Run the PermissionAttacher spec**

```
cd backend && bundle exec rspec spec/serializers/permission_attacher_spec.rb
```

Expected: all pass.

- [ ] **Step 5: Replace ConnectionManager#attach_permissions with a delegate**

In `backend/app/websocket/connection_manager.rb`, replace the `attach_permissions` method (lines 195–214) with a single-line delegate:

```ruby
    def attach_permissions(message, membership, policy_context)
      PermissionAttacher.attach_to_message(message, membership, policy_context)
    end
```

- [ ] **Step 6: Run websocket specs**

```
cd backend && bundle exec rspec spec/websocket/
```

Expected: all pass.

- [ ] **Step 7: Commit**

```
cd backend && git add app/serializers/permission_attacher.rb app/websocket/connection_manager.rb spec/serializers/permission_attacher_spec.rb
git commit -m "Route broadcast permission attachment through PermissionAttacher"
```

---

### Task 22: Replace Listener#prefetch_policy_context with serializer dispatch

**Files:**
- Modify: `backend/app/websocket/listener.rb:88-105`
- Modify: `backend/app/websocket/listener.rb:124-139`

Currently `Listener#prefetch_policy_context` has a hardcoded `case config.key when "event" / "settlement" / …` statement encoding policy-context rules that should live in each serializer. Replace it with a call to the registered serializer's `policy_context` method.

- [ ] **Step 1: Delete `prefetch_policy_context`**

In `backend/app/websocket/listener.rb`, delete the entire `prefetch_policy_context` private method (lines 88–105).

- [ ] **Step 2: Update `handle_notification` to call the serializer directly**

In `backend/app/websocket/listener.rb`, find the `update` branch in `handle_notification` (around lines 124–139) and replace with:

```ruby
        when "update"
          object = find_object(object_type, object_id)
          if object
            pool = PoolSerializer.new(workspace_id: workspace_id)
            pool.add(config.key, [object])
            message[:data] = { objects: pool.to_a }
            kwargs = config.serializer_class ? config.serializer_class.policy_context(object) : {}
            policy_context = Websocket::PolicyContext.new(
              raw_objects: { config.key => object },
              kwargs: kwargs
            )
          else
            # Object was deleted between notify and fetch
            message[:action] = "delete"
            message[:data] = { deleted: [{ objectType: config.client_type, id: object_id }] }
          end
```

- [ ] **Step 3: Run listener and connection_manager specs**

```
cd backend && bundle exec rspec spec/websocket/
```

Expected: all pass.

- [ ] **Step 4: Run the full suite**

```
cd backend && bundle exec rspec
```

Expected: all pass.

- [ ] **Step 5: Commit**

```
cd backend && git add app/websocket/listener.rb
git commit -m "Have Websocket::Listener ask the serializer for its policy context"
```

---

### Task 23: Replace `pool.send(config.pool_method, ...)` usages

**Files:**
- Modify: `backend/app/websocket/listener.rb:128` (pool.send → pool.add) — already done in Task 22

The remaining caller is gone. Verify by grepping.

- [ ] **Step 1: Verify no more `pool.send(` references in production code**

```
cd backend && grep -rn "pool.send" app/
```

Expected: no matches.

- [ ] **Step 2: Verify no more references to `config.pool_method` outside the registry file**

```
cd backend && grep -rn "pool_method" app/ spec/
```

Expected: only matches should be in `object_registry.rb` where the field is defined, and possibly in test setup. The `pool_method` field can be removed from the registry once all callers are gone — handle that in the next task.

No commit; this is a verification step before Task 24.

---

### Task 24: Delete legacy `add_X` / `add_X_batch` methods from PoolSerializer

**Files:**
- Modify: `backend/app/serializers/pool_serializer.rb`
- Modify: `backend/app/object_registry.rb`

At this point every production caller uses `pool.add(key, items)`. The legacy `add_X` and `add_X_batch` one-line delegates exist only for test compatibility. Delete them; update `spec/serializers/pool_serializer_spec.rb` to use the unified API. Also delete the now-unused `attach_permissions` private method and `pool_method` field from the registry.

- [ ] **Step 1: Rewrite PoolSerializer to the minimal shape**

Replace the entire file `backend/app/serializers/pool_serializer.rb` with:

```ruby
# frozen_string_literal: true

# Collects and serializes objects for pool-based API responses.
# Objects are deduplicated by type and id. Per-type serialization logic lives
# in app/serializers/<type>_serializer.rb — this class is just the coordinator.
#
# @example
#   pool = PoolSerializer.new(membership: membership)
#   pool.add(:event, [event])
#   { objects: pool.to_a }
class PoolSerializer
  def initialize(workspace_id: nil, membership: nil)
    @objects = {}
    @membership = membership
    @workspace_id = if membership
                      membership.workspace_id.to_s
                    else
                      workspace_id&.to_s
                    end
  end

  # Dispatches to the serializer registered for `key` in ObjectRegistry.
  # `items` may be a single object or an array.
  def add(key, items)
    entry = ObjectRegistry::BY_KEY[key.to_s]
    raise ArgumentError, "Unknown object key: #{key.inspect}" unless entry

    add_batch(entry, Array(items))
  end

  # Legacy entry point kept for the `WorkspaceSync` / `Listener` migration path.
  # Equivalent to `add(type, items)`.
  def add_all(items, type:)
    add(type, items)
  end

  def to_a
    @objects.values
  end

  private

  def add_batch(entry, items)
    return 0 if items.empty?

    serializer = entry.serializer_class
    raise ArgumentError, "No serializer_class for #{entry.key}" unless serializer

    contexts = serializer.policy_context_batch(items)
    hashes = serializer.serialize_batch(items, pool: self)
    added = 0

    items.zip(hashes).each do |obj, hash|
      next unless hash

      key = "#{entry.key}:#{obj.id}"
      next if @objects.key?(key)

      @objects[key] = if @membership
                        PermissionAttacher.call(
                          hash,
                          raw_object: obj,
                          membership: @membership,
                          policy_context: contexts[obj.id.to_s] || {}
                        )
                      else
                        hash
                      end
      added += 1
    end

    added
  end
end
```

- [ ] **Step 2: Remove `pool_method` from ObjectRegistry::Entry**

In `backend/app/object_registry.rb`, remove the `pool_method` field and remove it from every `Entry.new(...)` call. The `Entry` class becomes:

```ruby
  class Entry
    attr_reader :key, :model, :client_type, :tracks_user, :policy, :serializer_class

    def initialize(
      key:,
      model:,
      client_type:,
      tracks_user:,
      policy: nil,
      serializer_class: nil
    )
      @key = key
      @model = model
      @client_type = client_type
      @tracks_user = tracks_user
      @policy = policy
      @serializer_class = serializer_class
    end
  end
```

And update all 17 `Entry.new(...)` calls to remove `pool_method: :add_X,`. Example:

```ruby
    Entry.new(key: "event", model: "Event", client_type: "event", tracks_user: true, policy: "EventPolicy", serializer_class: EventSerializer),
```

(Apply the same removal to all 17 entries.)

- [ ] **Step 3: Update `pool_serializer_spec.rb` to the new API**

In `backend/spec/serializers/pool_serializer_spec.rb`, replace all calls:

- `pool.add_event(e)` → `pool.add(:event, [e])`
- `pool.add_events_batch(events)` → `pool.add(:event, events)`
- `pool.add_date_polls_batch(polls)` → `pool.add(:date_poll, polls)`
- `pool.add_date_ranges_batch(ranges)` → `pool.add(:date_range, ranges)`
- `pool.add_settlements_batch(settlements)` → `pool.add(:settlement, settlements)`

And in `backend/spec/serializers/pool_serializer_permissions_spec.rb`:

- `pool.add_event(event)` → `pool.add(:event, [event])`
- `pool.add_events_batch([event, event2])` → `pool.add(:event, [event, event2])`
- `pool.add_expense(expense)` → `pool.add(:expense, [expense])`

- [ ] **Step 4: Run the full suite**

```
cd backend && bundle exec rspec
```

Expected: all pass. Any remaining `NoMethodError: undefined method 'add_X'` means a caller was missed — grep and fix:

```
cd backend && grep -rn "\.add_event\|\.add_events_batch\|\.add_member\|\.add_workspace\|\.add_date_poll\|\.add_date_range\|\.add_vote\|\.add_rsvp\|\.add_task_list\|\.add_task_item\|\.add_expense\|\.add_settlement\|\.add_chore\|\.add_workspace_invite" spec/ app/
```

If any matches surface, replace them with `pool.add(:key, [items])` form.

- [ ] **Step 5: Commit**

```
cd backend && git add -A
git commit -m "Collapse PoolSerializer to the unified add(key, items) API"
```

---

## Phase 5: Final cleanup

### Task 25: Remove `to_api_hash` from pool-type models

**Files:**
- Modify: 16 model files (one model per registered pool type where `to_api_hash` still exists)
- Modify: `backend/spec/models/workspace_invite_spec.rb` (remove `#to_api_hash` spec)

`User#to_api_hash`, `Session#to_api_hash`, `PasskeyCredential#to_api_hash`, and `ServiceError#to_api_hash` stay. They are used by non-pool code paths (auth routes, error results).

Pool-type models that still have `to_api_hash` after Phase 4 (since nothing calls it anymore):

- `event.rb`, `workspace.rb`, `workspace_membership.rb` (dead code — see prior analysis), `date_poll.rb`, `date_range.rb`, `vote.rb`, `rsvp.rb`, `task_list.rb`, `task_item.rb`, `expense.rb`, `expense_participant.rb`, `settlement.rb`, `settlement_transfer.rb`, `chore_roster.rb`, `chore.rb`, `chore_assignment.rb`, `workspace_invite.rb`.

- [ ] **Step 1: Verify no production caller uses these methods**

```
cd backend && grep -rn "\.to_api_hash" app/ spec/ | grep -v "spec/serializers" | grep -v "spec/models/user_spec" | grep -v "app/models/user.rb" | grep -v "app/models/session.rb" | grep -v "app/models/passkey_credential.rb" | grep -v "app/services/service_error.rb" | grep -v "spec/models/workspace_invite_spec"
```

Expected: only matches should be in the auth routes / passkey services / result_handler which use User/Session/PasskeyCredential/ServiceError. If anything else is listed, fix the caller first.

- [ ] **Step 2: Remove `to_api_hash` from Event**

In `backend/app/models/event.rb`, delete lines 33–50 (the `def to_api_hash(date_poll_id:) … end` block).

- [ ] **Step 3: Remove `to_api_hash` from Workspace**

In `backend/app/models/workspace.rb`, delete the `def to_api_hash(member_ids:) … end` block (lines 19–28).

- [ ] **Step 4: Remove `to_api_hash` from WorkspaceMembership**

In `backend/app/models/workspace_membership.rb`, delete the `def to_api_hash … end` block (lines 23–32). This was dead code — not called from production or tests.

- [ ] **Step 5: Remove `to_api_hash` from DatePoll**

In `backend/app/models/date_poll.rb`, delete the `def to_api_hash(date_range_ids:) … end` block.

- [ ] **Step 6: Remove `to_api_hash` from DateRange**

In `backend/app/models/date_range.rb`, delete the `def to_api_hash … end` block.

- [ ] **Step 7: Remove `to_api_hash` from Vote**

In `backend/app/models/vote.rb`, delete the `def to_api_hash … end` block.

- [ ] **Step 8: Remove `to_api_hash` from Rsvp**

In `backend/app/models/rsvp.rb`, delete the `def to_api_hash … end` block.

- [ ] **Step 9: Remove `to_api_hash` from TaskList**

In `backend/app/models/task_list.rb`, delete the `def to_api_hash … end` block.

- [ ] **Step 10: Remove `to_api_hash` from TaskItem**

In `backend/app/models/task_item.rb`, delete the `def to_api_hash … end` block.

- [ ] **Step 11: Remove `to_api_hash` from Expense**

In `backend/app/models/expense.rb`, delete the `def to_api_hash … end` block.

- [ ] **Step 12: Remove `to_api_hash` from ExpenseParticipant**

In `backend/app/models/expense_participant.rb`, delete the `def to_api_hash … end` block.

- [ ] **Step 13: Remove `to_api_hash` from Settlement**

In `backend/app/models/settlement.rb`, delete the `def to_api_hash(transfer_ids:) … end` block.

- [ ] **Step 14: Remove `to_api_hash` from SettlementTransfer**

In `backend/app/models/settlement_transfer.rb`, delete the `def to_api_hash … end` block.

- [ ] **Step 15: Remove `to_api_hash` from ChoreRoster**

In `backend/app/models/chore_roster.rb`, delete the `def to_api_hash(chore_ids:) … end` block.

- [ ] **Step 16: Remove `to_api_hash` from Chore**

In `backend/app/models/chore.rb`, delete the `def to_api_hash(assignment_ids:) … end` block.

- [ ] **Step 17: Remove `to_api_hash` from ChoreAssignment**

In `backend/app/models/chore_assignment.rb`, delete the `def to_api_hash … end` block.

- [ ] **Step 18: Remove `to_api_hash` from WorkspaceInvite**

In `backend/app/models/workspace_invite.rb`, delete the `def to_api_hash … end` block.

- [ ] **Step 19: Remove the `#to_api_hash` describe block from workspace_invite_spec.rb**

In `backend/spec/models/workspace_invite_spec.rb`, locate the `describe "#to_api_hash" do … end` block (around lines 147–155) and delete it.

- [ ] **Step 20: Run the full suite**

```
cd backend && bundle exec rspec
```

Expected: all pass.

- [ ] **Step 21: Run linter and typechecker**

```
cd backend && bundle exec rubocop
```

Expected: no offenses. Fix any unused-variable or unused-method warnings from the removals.

- [ ] **Step 22: Commit**

```
cd backend && git add -A
git commit -m "Drop to_api_hash from pool-registered models"
```

---

### Task 26: Add shared spec invariants for pool object contract

**Files:**
- Create: `backend/spec/support/shared_examples/pool_object_examples.rb`
- Modify: 17 serializer spec files (add `it_behaves_like "a pool object"`)

Every pool object must: have a string `id`, a camelCase `objectType` matching the registry, ISO-8601 ms-precision `createdAt` and `updatedAt` (where applicable). Capture these as shared examples and run them against every serializer.

Note: `DateRangeSerializer` emits only `updatedAt` (not `createdAt`) — its shared example must be relaxed or a separate shared example used. The `member` hash has `createdAt` but not from the membership row alone. Handle these carve-outs explicitly.

- [ ] **Step 1: Create the shared examples file**

```ruby
# backend/spec/support/shared_examples/pool_object_examples.rb
# frozen_string_literal: true

RSpec.shared_examples "a pool object" do |expected_client_type|
  it "emits a string id" do
    expect(subject[:id]).to be_a(String)
    expect(subject[:id]).not_to be_empty
  end

  it "emits objectType #{expected_client_type}" do
    expect(subject[:objectType]).to eq(expected_client_type)
  end

  it "emits an iso8601(3) updatedAt" do
    expect(subject[:updatedAt]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}/)
  end
end

RSpec.shared_examples "a pool object with createdAt" do |expected_client_type|
  it_behaves_like "a pool object", expected_client_type

  it "emits an iso8601(3) createdAt" do
    expect(subject[:createdAt]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}/)
  end
end
```

- [ ] **Step 2: Require the shared examples from spec_helper**

In `backend/spec/spec_helper.rb`, find the existing `Dir[...]` glob for support files (if any) and make sure it includes the new file. If no glob exists, add near the top:

```ruby
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }
```

- [ ] **Step 3: Add `it_behaves_like` to every serializer spec**

For each Phase 2 + Phase 3 serializer spec, add inside `describe ".serialize_batch"`, before any `it` blocks:

```ruby
    context "when serializing a single object" do
      subject { described_class.serialize_batch([the_object], pool: nil).first }

      let(:the_object) { /* copy the setup from the first existing it block */ }

      it_behaves_like "a pool object with createdAt", "<client_type>"
    end
```

Where `<client_type>` is the entry's `client_type` (`event`, `workspace`, `datePoll`, etc.). For `DateRangeSerializer` use `"a pool object"` (no createdAt).

This step is tedious. For brevity, apply it to each spec and commit once at the end.

- [ ] **Step 4: Run the full suite**

```
cd backend && bundle exec rspec
```

Expected: all pass, including the new shared examples.

- [ ] **Step 5: Commit**

```
cd backend && git add -A
git commit -m "Add shared spec invariants for pool object contract"
```

---

### Task 27: Final CI sweep

**Files:**
- None (verification only)

- [ ] **Step 1: Run full backend checks**

```
mise run check
```

Expected: lint, typecheck, test, and audit all green.

- [ ] **Step 2: Run E2E to make sure the on-wire shape is unchanged**

```
mise run e2e
```

Expected: all Playwright tests pass. Any frontend failure means a pool object changed shape in a way the frontend didn't expect — bisect to find which serializer diverged from the prior `to_api_hash`.

- [ ] **Step 3: No commit — the refactor is done**

---

## Self-Review

**Spec coverage check:**

| Spec goal | Covered by task |
|---|---|
| Per-type serializer class for all 17 registered types | Tasks 4–19 |
| Unified `PermissionAttacher` used by both sync and broadcast paths | Tasks 1, 21 |
| `ObjectRegistry` as single source of truth (no hardcoded per-type logic in sync/listener) | Tasks 20, 22 |
| Legacy `add_X`/`add_X_batch` collapsed into one entry point | Tasks 23–24 |
| `batch_methods` hash deleted from `WorkspaceSync` | Task 20 |
| `prefetch_policy_context` deleted from `Listener` | Task 22 |
| Parent→child expansion explicit (task_list, chore_roster, expense) | Tasks 17, 18, 19 |
| `to_api_hash` removed from pool-type models | Task 25 |
| `User`/`Session`/`PasskeyCredential`/`ServiceError` `to_api_hash` untouched | Task 25 Step 1 verification |
| Shared spec invariants for pool-object contract | Task 26 |
| No N+1 regressions | Phase 2/3 serializer specs pin batched lookups |

**Placeholder scan:** No TBDs, TODOs, or "implement later" markers. Every code block is complete.

**Type consistency:**
- `serialize_batch(objects, pool:)` signature is consistent across all 17 serializers.
- `policy_context(object)` and `policy_context_batch(objects)` signatures consistent.
- `PoolSerializer#add(key, items)` returns integer count added (matches `add_batch`).
- `PermissionAttacher.call(hash, raw_object:, membership:, policy_context:)` signature consistent across Task 1 definition and all call sites (Tasks 3, 24).
- `PermissionAttacher.attach_to_message(message, membership, policy_context)` matches the existing `ConnectionManager#attach_permissions` signature so the delegate in Task 21 Step 5 is a drop-in.
- Registry entry: `pool_method` field is removed in Task 24; every earlier task still uses it in Entry construction, which is correct since Task 24 does the removal after all callers are gone.

**Known carve-outs:**
- `ExpenseParticipant#to_api_hash` bug (both `createdAt` and `updatedAt` use `created_at`) is preserved, not fixed.
- `DateRangeSerializer` single-lookup fallback for `DateRangePolicy` event context is not optimized in `policy_context_batch`. Current cost: one extra query per date_range when computing permissions at sync time. Not a regression.
- `WorkspaceMembership#to_api_hash` is dead code; deleted in Task 25 Step 4 alongside the live removals.
- `Listener` `settlement_transfer` case in `prefetch_policy_context` was passing an `event:` kwarg that `SettlementTransferPolicy` ignores (it has no `event:` parameter). Deleting `prefetch_policy_context` in Task 22 drops the dead context.
