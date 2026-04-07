# Permission System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace scattered inline permission checks with a policy-class system where the backend is the single source of truth for all permissions.

**Architecture:** Policy classes (one per object type) return Dry::Monads Result values. Services call policies for enforcement; PoolSerializer calls them for serialization. The frontend reads `permissions` from pool objects and never computes permissions itself.

**Tech Stack:** Ruby, Dry::Monads, Roda, Sequel, Vue 3, TypeScript, Pinia

---

### Task 1: Policy Module

The shared base module that all policy classes include. Provides the generic `permissions` method and Result-to-hash conversion.

**Files:**

- Create: `backend/app/policies/policy.rb`
- Test: `backend/spec/policies/policy_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# backend/spec/policies/policy_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Policy module" do
  let(:test_policy_class) do
    Class.new do
      include Policy

      ACTIONS = %i[edit delete].freeze

      def initialize(allowed_edit:, allowed_delete:)
        @allowed_edit = allowed_edit
        @allowed_delete = allowed_delete
      end

      def edit
        if @allowed_edit
          Success()
        else
          Failure(:not_owner)
        end
      end

      def delete
        if @allowed_delete
          Success()
        else
          Failure(:has_settlements)
        end
      end
    end
  end

  describe "#permissions" do
    it "returns allowed: true for successful actions" do
      policy = test_policy_class.new(allowed_edit: true, allowed_delete: true)

      expect(policy.permissions).to eq(
        edit: { allowed: true },
        delete: { allowed: true }
      )
    end

    it "returns allowed: false with reason for failed actions" do
      policy = test_policy_class.new(allowed_edit: false, allowed_delete: false)

      expect(policy.permissions).to eq(
        edit: { allowed: false, reason: "not_owner" },
        delete: { allowed: false, reason: "has_settlements" }
      )
    end

    it "handles mixed results" do
      policy = test_policy_class.new(allowed_edit: true, allowed_delete: false)

      expect(policy.permissions).to eq(
        edit: { allowed: true },
        delete: { allowed: false, reason: "has_settlements" }
      )
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && bundle exec rspec spec/policies/policy_spec.rb -v`
Expected: FAIL — `Policy` module not defined.

- [ ] **Step 3: Write the Policy module**

```ruby
# backend/app/policies/policy.rb
# frozen_string_literal: true

# Base module for all policy classes. Each policy declares an ACTIONS constant
# listing its permission methods. Each method returns Success() or Failure(:reason).
#
# @example
#   class EventPolicy
#     include Policy
#     ACTIONS = %i[edit delete].freeze
#
#     def edit
#       if @owner then Success() else Failure(:not_owner) end
#     end
#   end
#
#   EventPolicy.new(event, membership: m).permissions
#   # => { edit: { allowed: true }, delete: { allowed: false, reason: "not_owner" } }
module Policy
  include Dry::Monads[:result]

  def permissions
    self.class::ACTIONS.each_with_object({}) do |action, hash|
      hash[action] = to_permission(send(action))
    end
  end

  private

  def to_permission(result)
    case result
    in Success
      { allowed: true }
    in Failure(reason)
      { allowed: false, reason: reason.to_s }
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && bundle exec rspec spec/policies/policy_spec.rb -v`
Expected: PASS — all 3 examples pass.

- [ ] **Step 5: Commit**

```
git add backend/app/policies/policy.rb backend/spec/policies/policy_spec.rb
git commit -m "Add Policy base module for permission system"
```

---

### Task 2: EventPolicy

The first real policy class. Covers edit, delete, and all child-creation actions on events.

**Files:**

- Create: `backend/app/policies/event_policy.rb`
- Test: `backend/spec/policies/event_policy_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# backend/spec/policies/event_policy_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe EventPolicy do
  let(:workspace) { TestFactories.workspace }
  let(:owner) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:owner_membership) { TestFactories.workspace_membership(workspace: workspace, user: owner) }
  let(:other_membership) { TestFactories.workspace_membership(workspace: workspace, user: other_user) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: owner) }
  let(:event) { Event.find(event_row[:id]) }

  describe "#edit" do
    it "allows the event owner" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.edit).to be_success
    end

    it "rejects non-owners" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(other_membership[:id]))
      expect(policy.edit).to be_failure
      expect(policy.edit.failure).to eq(:not_owner)
    end
  end

  describe "#delete" do
    it "allows the event owner" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.delete).to be_success
    end

    it "rejects non-owners" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(other_membership[:id]))
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:not_owner)
    end
  end

  describe "#create_poll" do
    it "allows the event owner" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.create_poll).to be_success
    end

    it "rejects non-owners" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(other_membership[:id]))
      expect(policy.create_poll).to be_failure
    end
  end

  describe "#permissions" do
    it "returns a hash of all actions" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(owner_membership[:id]))
      perms = policy.permissions

      expect(perms.keys).to contain_exactly(
        :edit, :delete, :create_poll, :create_expense, :create_settlement,
        :create_rsvp, :create_chore_roster, :create_task_list
      )
      expect(perms[:edit]).to eq({ allowed: true })
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && bundle exec rspec spec/policies/event_policy_spec.rb -v`
Expected: FAIL — `EventPolicy` not defined.

- [ ] **Step 3: Write EventPolicy**

```ruby
# backend/app/policies/event_policy.rb
# frozen_string_literal: true

class EventPolicy
  include Policy

  ACTIONS = %i[edit delete create_poll create_expense create_settlement
               create_rsvp create_chore_roster create_task_list].freeze

  def initialize(event, membership:, **)
    @event = event
    @owner = event.user_id == membership.user_id
  end

  def edit
    if @owner
      Success()
    else
      Failure(:not_owner)
    end
  end

  def delete
    if @owner
      Success()
    else
      Failure(:not_owner)
    end
  end

  def create_poll
    if @owner
      Success()
    else
      Failure(:not_owner)
    end
  end

  def create_expense
    Success()
  end

  def create_settlement
    Success()
  end

  def create_rsvp
    Success()
  end

  def create_chore_roster
    Success()
  end

  def create_task_list
    Success()
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && bundle exec rspec spec/policies/event_policy_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add backend/app/policies/event_policy.rb backend/spec/policies/event_policy_spec.rb
git commit -m "Add EventPolicy for event permission checks"
```

---

### Task 3: ExpensePolicy

Covers edit and delete with ownership + settlement state checks.

**Files:**

- Create: `backend/app/policies/expense_policy.rb`
- Test: `backend/spec/policies/expense_policy_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# backend/spec/policies/expense_policy_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExpensePolicy do
  let(:workspace) { TestFactories.workspace }
  let(:owner) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:owner_membership) { TestFactories.workspace_membership(workspace: workspace, user: owner) }
  let(:other_membership) { TestFactories.workspace_membership(workspace: workspace, user: other_user) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: owner) }

  def create_expense(user:, settlement_id: nil)
    now = Time.now
    id = SecureRandom.uuid
    DB[:expenses].insert(
      id: id, event_id: event_row[:id], user_id: user[:id],
      description: "Test", amount: 10.0,
      start_date: Date.today, end_date: Date.today,
      settlement_id: settlement_id,
      created_at: now, updated_at: now
    )
    Expense.find(id)
  end

  describe "#edit" do
    it "allows the expense creator" do
      expense = create_expense(user: owner)
      policy = described_class.new(expense, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.edit).to be_success
    end

    it "rejects non-creators" do
      expense = create_expense(user: owner)
      policy = described_class.new(expense, membership: WorkspaceMembership.find(other_membership[:id]))
      expect(policy.edit).to be_failure
      expect(policy.edit.failure).to eq(:not_creator)
    end

    it "rejects when expense is settled" do
      expense = create_expense(user: owner, settlement_id: SecureRandom.uuid)
      policy = described_class.new(expense, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.edit).to be_failure
      expect(policy.edit.failure).to eq(:settled)
    end
  end

  describe "#delete" do
    it "allows the expense creator" do
      expense = create_expense(user: owner)
      policy = described_class.new(expense, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.delete).to be_success
    end

    it "rejects when settled even for creator" do
      expense = create_expense(user: owner, settlement_id: SecureRandom.uuid)
      policy = described_class.new(expense, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:settled)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && bundle exec rspec spec/policies/expense_policy_spec.rb -v`
Expected: FAIL — `ExpensePolicy` not defined.

- [ ] **Step 3: Write ExpensePolicy**

```ruby
# backend/app/policies/expense_policy.rb
# frozen_string_literal: true

class ExpensePolicy
  include Policy

  ACTIONS = %i[edit delete].freeze

  def initialize(expense, membership:, **)
    @expense = expense
    @creator = expense.user_id == membership.user_id
    @settled = !expense.settlement_id.nil?
  end

  def edit
    if @settled
      Failure(:settled)
    elsif @creator
      Success()
    else
      Failure(:not_creator)
    end
  end

  def delete
    if @settled
      Failure(:settled)
    elsif @creator
      Success()
    else
      Failure(:not_creator)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && bundle exec rspec spec/policies/expense_policy_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add backend/app/policies/expense_policy.rb backend/spec/policies/expense_policy_spec.rb
git commit -m "Add ExpensePolicy for expense permission checks"
```

---

### Task 4: SettlementPolicy

Covers delete with creator-or-event-owner logic. Takes optional `event:` kwarg to avoid extra queries when pre-fetched.

**Files:**

- Create: `backend/app/policies/settlement_policy.rb`
- Test: `backend/spec/policies/settlement_policy_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# backend/spec/policies/settlement_policy_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementPolicy do
  let(:workspace) { TestFactories.workspace }
  let(:event_owner) { TestFactories.user }
  let(:settlement_creator) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:event_owner_membership) { TestFactories.workspace_membership(workspace: workspace, user: event_owner) }
  let(:creator_membership) { TestFactories.workspace_membership(workspace: workspace, user: settlement_creator) }
  let(:other_membership) { TestFactories.workspace_membership(workspace: workspace, user: other_user) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: event_owner) }
  let(:event) { Event.find(event_row[:id]) }

  def create_settlement(user:)
    now = Time.now
    id = SecureRandom.uuid
    DB[:settlements].insert(id: id, event_id: event_row[:id], user_id: user[:id], created_at: now, updated_at: now)
    Settlement.find(id)
  end

  describe "#delete" do
    it "allows the settlement creator" do
      settlement = create_settlement(user: settlement_creator)
      policy = described_class.new(settlement, membership: WorkspaceMembership.find(creator_membership[:id]), event: event)
      expect(policy.delete).to be_success
    end

    it "allows the event owner" do
      settlement = create_settlement(user: settlement_creator)
      policy = described_class.new(settlement, membership: WorkspaceMembership.find(event_owner_membership[:id]), event: event)
      expect(policy.delete).to be_success
    end

    it "rejects other users" do
      settlement = create_settlement(user: settlement_creator)
      policy = described_class.new(settlement, membership: WorkspaceMembership.find(other_membership[:id]), event: event)
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:not_creator_or_event_owner)
    end

    it "fetches event when not provided" do
      settlement = create_settlement(user: settlement_creator)
      policy = described_class.new(settlement, membership: WorkspaceMembership.find(creator_membership[:id]))
      expect(policy.delete).to be_success
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && bundle exec rspec spec/policies/settlement_policy_spec.rb -v`
Expected: FAIL — `SettlementPolicy` not defined.

- [ ] **Step 3: Write SettlementPolicy**

```ruby
# backend/app/policies/settlement_policy.rb
# frozen_string_literal: true

class SettlementPolicy
  include Policy

  ACTIONS = %i[delete].freeze

  def initialize(settlement, membership:, event: nil, **)
    @settlement = settlement
    @event = event || Event.find(settlement.event_id)
    @creator = settlement.user_id == membership.user_id
    @event_owner = @event&.user_id == membership.user_id
  end

  def delete
    if @creator || @event_owner
      Success()
    else
      Failure(:not_creator_or_event_owner)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && bundle exec rspec spec/policies/settlement_policy_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add backend/app/policies/settlement_policy.rb backend/spec/policies/settlement_policy_spec.rb
git commit -m "Add SettlementPolicy for settlement permission checks"
```

---

### Task 5: SettlementTransferPolicy

Covers mark_paid — only the transfer recipient can mark it.

**Files:**

- Create: `backend/app/policies/settlement_transfer_policy.rb`
- Test: `backend/spec/policies/settlement_transfer_policy_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# backend/spec/policies/settlement_transfer_policy_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementTransferPolicy do
  let(:workspace) { TestFactories.workspace }
  let(:recipient) { TestFactories.user }
  let(:sender) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:recipient_membership) { TestFactories.workspace_membership(workspace: workspace, user: recipient) }
  let(:sender_membership) { TestFactories.workspace_membership(workspace: workspace, user: sender) }
  let(:other_membership) { TestFactories.workspace_membership(workspace: workspace, user: other_user) }

  def create_transfer(from_user:, to_user:)
    event_row = TestFactories.event(workspace: workspace, user: from_user)
    now = Time.now
    settlement_id = SecureRandom.uuid
    DB[:settlements].insert(id: settlement_id, event_id: event_row[:id], user_id: from_user[:id], created_at: now, updated_at: now)
    transfer_id = SecureRandom.uuid
    DB[:settlement_transfers].insert(
      id: transfer_id, settlement_id: settlement_id,
      from_user_id: from_user[:id], to_user_id: to_user[:id],
      amount: 50.0, created_at: now, updated_at: now
    )
    SettlementTransfer.find(transfer_id)
  end

  describe "#mark_paid" do
    it "allows the transfer recipient" do
      transfer = create_transfer(from_user: sender, to_user: recipient)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(recipient_membership[:id]))
      expect(policy.mark_paid).to be_success
    end

    it "rejects the sender" do
      transfer = create_transfer(from_user: sender, to_user: recipient)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(sender_membership[:id]))
      expect(policy.mark_paid).to be_failure
      expect(policy.mark_paid.failure).to eq(:not_recipient)
    end

    it "rejects other users" do
      transfer = create_transfer(from_user: sender, to_user: recipient)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(other_membership[:id]))
      expect(policy.mark_paid).to be_failure
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && bundle exec rspec spec/policies/settlement_transfer_policy_spec.rb -v`
Expected: FAIL — `SettlementTransferPolicy` not defined.

- [ ] **Step 3: Write SettlementTransferPolicy**

```ruby
# backend/app/policies/settlement_transfer_policy.rb
# frozen_string_literal: true

class SettlementTransferPolicy
  include Policy

  ACTIONS = %i[mark_paid].freeze

  def initialize(transfer, membership:, **)
    @transfer = transfer
    @recipient = transfer.to_user_id == membership.user_id
  end

  def mark_paid
    if @recipient
      Success()
    else
      Failure(:not_recipient)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && bundle exec rspec spec/policies/settlement_transfer_policy_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add backend/app/policies/settlement_transfer_policy.rb backend/spec/policies/settlement_transfer_policy_spec.rb
git commit -m "Add SettlementTransferPolicy for transfer permission checks"
```

---

### Task 6: MemberPolicy

Covers change_role with hierarchical role logic, plus the non-boolean `availableRoles`.

**Files:**

- Create: `backend/app/policies/member_policy.rb`
- Test: `backend/spec/policies/member_policy_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# backend/spec/policies/member_policy_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe MemberPolicy do
  let(:workspace) { TestFactories.workspace }
  let(:owner_user) { TestFactories.user }
  let(:admin_user) { TestFactories.user }
  let(:member_user) { TestFactories.user }
  let(:target_user) { TestFactories.user }
  let(:owner_row) { TestFactories.workspace_membership(workspace: workspace, user: owner_user, role: "owner") }
  let(:admin_row) { TestFactories.workspace_membership(workspace: workspace, user: admin_user, role: "admin") }
  let(:member_row) { TestFactories.workspace_membership(workspace: workspace, user: member_user, role: "member") }
  let(:target_member_row) { TestFactories.workspace_membership(workspace: workspace, user: target_user, role: "member") }
  let(:target_admin_row) { TestFactories.workspace_membership(workspace: workspace, user: target_user, role: "admin") }

  def membership(row)
    WorkspaceMembership.find(row[:id])
  end

  describe "#change_role" do
    it "allows owner to change any member's role" do
      policy = described_class.new(membership(target_member_row), membership: membership(owner_row))
      expect(policy.change_role).to be_success
    end

    it "allows admin to change member's role" do
      policy = described_class.new(membership(target_member_row), membership: membership(admin_row))
      expect(policy.change_role).to be_success
    end

    it "prevents admin from changing owner's role" do
      policy = described_class.new(membership(owner_row), membership: membership(admin_row))
      expect(policy.change_role).to be_failure
      expect(policy.change_role.failure).to eq(:cannot_change_owner)
    end

    it "prevents member from changing any role" do
      policy = described_class.new(membership(target_member_row), membership: membership(member_row))
      expect(policy.change_role).to be_failure
      expect(policy.change_role.failure).to eq(:not_admin_or_owner)
    end

    it "prevents changing own role" do
      policy = described_class.new(membership(owner_row), membership: membership(owner_row))
      expect(policy.change_role).to be_failure
      expect(policy.change_role.failure).to eq(:cannot_change_own_role)
    end
  end

  describe "#available_roles" do
    it "returns all roles for owner" do
      policy = described_class.new(membership(target_member_row), membership: membership(owner_row))
      expect(policy.available_roles).to eq(%w[member admin owner])
    end

    it "returns member and admin for admin" do
      policy = described_class.new(membership(target_member_row), membership: membership(admin_row))
      expect(policy.available_roles).to eq(%w[member admin])
    end

    it "returns empty for member" do
      policy = described_class.new(membership(target_member_row), membership: membership(member_row))
      expect(policy.available_roles).to eq([])
    end

    it "returns empty when changing own role" do
      policy = described_class.new(membership(owner_row), membership: membership(owner_row))
      expect(policy.available_roles).to eq([])
    end
  end

  describe "#permissions" do
    it "includes availableRoles in the permissions hash" do
      policy = described_class.new(membership(target_member_row), membership: membership(owner_row))
      perms = policy.permissions

      expect(perms[:change_role]).to eq({ allowed: true })
      expect(perms[:availableRoles]).to eq(%w[member admin owner])
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && bundle exec rspec spec/policies/member_policy_spec.rb -v`
Expected: FAIL — `MemberPolicy` not defined.

- [ ] **Step 3: Write MemberPolicy**

```ruby
# backend/app/policies/member_policy.rb
# frozen_string_literal: true

class MemberPolicy
  include Policy

  ACTIONS = %i[change_role].freeze

  def initialize(target_member, membership:, **)
    @target = target_member
    @membership = membership
    @role = membership.role
    @self_change = target_member.user_id == membership.user_id
  end

  def change_role
    if @self_change
      Failure(:cannot_change_own_role)
    elsif !%w[admin owner].include?(@role)
      Failure(:not_admin_or_owner)
    elsif @target.role == "owner" && @role != "owner"
      Failure(:cannot_change_owner)
    else
      Success()
    end
  end

  def available_roles
    if change_role.failure?
      []
    else
      case @role
      when "owner" then %w[member admin owner]
      when "admin" then %w[member admin]
      else []
      end
    end
  end

  def permissions
    super.merge(availableRoles: available_roles)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && bundle exec rspec spec/policies/member_policy_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add backend/app/policies/member_policy.rb backend/spec/policies/member_policy_spec.rb
git commit -m "Add MemberPolicy for role change permission checks"
```

---

### Task 7: Remaining Policy Classes

Create the remaining simpler policies. Each follows the same pattern — ownership check with `if`/`else`.

**Files:**

- Create: `backend/app/policies/date_poll_policy.rb`
- Create: `backend/app/policies/date_range_policy.rb`
- Create: `backend/app/policies/vote_policy.rb`
- Create: `backend/app/policies/rsvp_policy.rb`
- Create: `backend/app/policies/workspace_policy.rb`
- Create: `backend/app/policies/workspace_invite_policy.rb`
- Create: `backend/app/policies/chore_roster_policy.rb`
- Create: `backend/app/policies/chore_policy.rb`
- Create: `backend/app/policies/chore_assignment_policy.rb`
- Create: `backend/app/policies/task_list_policy.rb`
- Create: `backend/app/policies/task_item_policy.rb`
- Create: `backend/app/policies/expense_participant_policy.rb`
- Test: `backend/spec/policies/remaining_policies_spec.rb`

- [ ] **Step 1: Write tests for all remaining policies**

```ruby
# backend/spec/policies/remaining_policies_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Remaining policies" do
  let(:workspace) { TestFactories.workspace }
  let(:user_a) { TestFactories.user }
  let(:user_b) { TestFactories.user }
  let(:membership_a) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: user_a, role: "member")[:id]) }
  let(:admin_membership) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: user_a, role: "admin")[:id]) }
  let(:membership_b) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: user_b, role: "member")[:id]) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: user_a) }
  let(:event) { Event.find(event_row[:id]) }

  describe DatePollPolicy do
    let(:poll_row) { TestFactories.date_poll(event: event_row) }
    let(:poll) { DatePoll.find(poll_row[:id]) }

    it "allows event owner to close" do
      policy = described_class.new(poll, membership: membership_a, event: event)
      expect(policy.close).to be_success
    end

    it "rejects non-event-owner from closing" do
      policy = described_class.new(poll, membership: membership_b, event: event)
      expect(policy.close).to be_failure
      expect(policy.close.failure).to eq(:not_event_owner)
    end

    it "has correct ACTIONS" do
      expect(described_class::ACTIONS).to contain_exactly(:close, :reopen, :create_date_range)
    end
  end

  describe DateRangePolicy do
    let(:poll_row) { TestFactories.date_poll(event: event_row) }
    let(:range_row) { TestFactories.date_range(date_poll: poll_row) }
    let(:range) { DateRange.find(range_row[:id]) }

    it "allows event owner to delete" do
      policy = described_class.new(range, membership: membership_a, event: event)
      expect(policy.delete).to be_success
    end

    it "rejects non-event-owner from deleting" do
      policy = described_class.new(range, membership: membership_b, event: event)
      expect(policy.delete).to be_failure
    end

    it "has correct ACTIONS" do
      expect(described_class::ACTIONS).to contain_exactly(:delete, :create_vote)
    end
  end

  describe VotePolicy do
    let(:poll_row) { TestFactories.date_poll(event: event_row) }
    let(:range_row) { TestFactories.date_range(date_poll: poll_row) }
    let(:vote_row) { TestFactories.vote(date_range: range_row, user: user_a) }
    let(:vote) { Vote.find(vote_row[:id]) }

    it "allows vote creator to delete" do
      policy = described_class.new(vote, membership: membership_a)
      expect(policy.delete).to be_success
    end

    it "rejects non-creators" do
      policy = described_class.new(vote, membership: membership_b)
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:not_creator)
    end
  end

  describe RsvpPolicy do
    let(:rsvp_row) { TestFactories.rsvp(event: event_row, user: user_a) }
    let(:rsvp) { Rsvp.find(rsvp_row[:id]) }

    it "allows rsvp creator to delete" do
      policy = described_class.new(rsvp, membership: membership_a)
      expect(policy.delete).to be_success
    end

    it "rejects non-creators" do
      policy = described_class.new(rsvp, membership: membership_b)
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:not_creator)
    end
  end

  describe WorkspacePolicy do
    it "allows any member to create events" do
      policy = described_class.new(workspace, membership: membership_a)
      expect(policy.create_event).to be_success
    end

    it "allows admins to invite" do
      policy = described_class.new(workspace, membership: admin_membership)
      expect(policy.invite).to be_success
    end

    it "rejects members from inviting" do
      policy = described_class.new(workspace, membership: membership_a)
      expect(policy.invite).to be_failure
      expect(policy.invite.failure).to eq(:not_admin_or_owner)
    end

    it "has correct ACTIONS" do
      expect(described_class::ACTIONS).to contain_exactly(:create_event, :invite, :manage_members)
    end
  end

  describe WorkspaceInvitePolicy do
    it "allows admins to delete and remind" do
      invite_row = TestFactories.workspace_membership(workspace: workspace, user: user_a, role: "admin")
      admin = WorkspaceMembership.find(invite_row[:id])
      # WorkspaceInvitePolicy takes the invite object but checks the acting user's role
      policy = described_class.new(nil, membership: admin)
      expect(policy.delete).to be_success
      expect(policy.remind).to be_success
    end

    it "rejects members" do
      policy = described_class.new(nil, membership: membership_a)
      expect(policy.delete).to be_failure
    end
  end

  describe ChoreRosterPolicy do
    let(:roster_row) { TestFactories.chore_roster(event: event_row, user: user_a) }
    let(:roster) { ChoreRoster.find(roster_row[:id]) }

    it "allows roster creator to delete" do
      policy = described_class.new(roster, membership: membership_a)
      expect(policy.delete).to be_success
    end

    it "allows any member to create chores" do
      policy = described_class.new(roster, membership: membership_b)
      expect(policy.create_chore).to be_success
    end

    it "has correct ACTIONS" do
      expect(described_class::ACTIONS).to contain_exactly(:edit, :delete, :create_chore)
    end
  end

  describe TaskListPolicy do
    it "allows any member to edit and delete" do
      task_list_row = TestFactories.task_list(workspace: workspace, user: user_a)
      task_list = TaskList.find(task_list_row[:id])
      policy = described_class.new(task_list, membership: membership_b)
      expect(policy.edit).to be_success
      expect(policy.delete).to be_success
      expect(policy.create_task_item).to be_success
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && bundle exec rspec spec/policies/remaining_policies_spec.rb -v`
Expected: FAIL — classes not defined.

- [ ] **Step 3: Write all remaining policy classes**

```ruby
# backend/app/policies/date_poll_policy.rb
# frozen_string_literal: true

class DatePollPolicy
  include Policy

  ACTIONS = %i[close reopen create_date_range].freeze

  def initialize(date_poll, membership:, event: nil, **)
    @date_poll = date_poll
    @event = event || Event.find(date_poll.event_id)
    @event_owner = @event&.user_id == membership.user_id
  end

  def close
    if @event_owner
      Success()
    else
      Failure(:not_event_owner)
    end
  end

  def reopen
    if @event_owner
      Success()
    else
      Failure(:not_event_owner)
    end
  end

  def create_date_range
    if @event_owner
      Success()
    else
      Failure(:not_event_owner)
    end
  end
end
```

```ruby
# backend/app/policies/date_range_policy.rb
# frozen_string_literal: true

class DateRangePolicy
  include Policy

  ACTIONS = %i[delete create_vote].freeze

  def initialize(date_range, membership:, event: nil, **)
    @date_range = date_range
    if event
      @event_owner = event.user_id == membership.user_id
    else
      poll = DatePoll.find(date_range.date_poll_id)
      found_event = Event.find(poll.event_id) if poll
      @event_owner = found_event&.user_id == membership.user_id
    end
  end

  def delete
    if @event_owner
      Success()
    else
      Failure(:not_event_owner)
    end
  end

  def create_vote
    Success()
  end
end
```

```ruby
# backend/app/policies/vote_policy.rb
# frozen_string_literal: true

class VotePolicy
  include Policy

  ACTIONS = %i[delete].freeze

  def initialize(vote, membership:, **)
    @creator = vote.user_id == membership.user_id
  end

  def delete
    if @creator
      Success()
    else
      Failure(:not_creator)
    end
  end
end
```

```ruby
# backend/app/policies/rsvp_policy.rb
# frozen_string_literal: true

class RsvpPolicy
  include Policy

  ACTIONS = %i[delete].freeze

  def initialize(rsvp, membership:, **)
    @creator = rsvp.user_id == membership.user_id
  end

  def delete
    if @creator
      Success()
    else
      Failure(:not_creator)
    end
  end
end
```

```ruby
# backend/app/policies/workspace_policy.rb
# frozen_string_literal: true

class WorkspacePolicy
  include Policy

  ACTIONS = %i[create_event invite manage_members].freeze

  def initialize(_workspace, membership:, **)
    @admin_or_owner = %w[admin owner].include?(membership.role)
  end

  def create_event
    Success()
  end

  def invite
    if @admin_or_owner
      Success()
    else
      Failure(:not_admin_or_owner)
    end
  end

  def manage_members
    if @admin_or_owner
      Success()
    else
      Failure(:not_admin_or_owner)
    end
  end
end
```

```ruby
# backend/app/policies/workspace_invite_policy.rb
# frozen_string_literal: true

class WorkspaceInvitePolicy
  include Policy

  ACTIONS = %i[delete remind].freeze

  def initialize(_invite, membership:, **)
    @admin_or_owner = %w[admin owner].include?(membership.role)
  end

  def delete
    if @admin_or_owner
      Success()
    else
      Failure(:not_admin_or_owner)
    end
  end

  def remind
    if @admin_or_owner
      Success()
    else
      Failure(:not_admin_or_owner)
    end
  end
end
```

```ruby
# backend/app/policies/chore_roster_policy.rb
# frozen_string_literal: true

class ChoreRosterPolicy
  include Policy

  ACTIONS = %i[edit delete create_chore].freeze

  def initialize(roster, membership:, **)
    @creator = roster&.user_id == membership.user_id
  end

  def edit
    Success()
  end

  def delete
    if @creator
      Success()
    else
      Failure(:not_creator)
    end
  end

  def create_chore
    Success()
  end
end
```

```ruby
# backend/app/policies/chore_policy.rb
# frozen_string_literal: true

class ChorePolicy
  include Policy

  ACTIONS = %i[edit delete].freeze

  def initialize(_chore, membership:, **)
  end

  def edit
    Success()
  end

  def delete
    Success()
  end
end
```

```ruby
# backend/app/policies/chore_assignment_policy.rb
# frozen_string_literal: true

class ChoreAssignmentPolicy
  include Policy

  ACTIONS = %i[edit delete].freeze

  def initialize(_assignment, membership:, **)
  end

  def edit
    Success()
  end

  def delete
    Success()
  end
end
```

```ruby
# backend/app/policies/task_list_policy.rb
# frozen_string_literal: true

class TaskListPolicy
  include Policy

  ACTIONS = %i[edit delete create_task_item].freeze

  def initialize(_task_list, membership:, **)
  end

  def edit
    Success()
  end

  def delete
    Success()
  end

  def create_task_item
    Success()
  end
end
```

```ruby
# backend/app/policies/task_item_policy.rb
# frozen_string_literal: true

class TaskItemPolicy
  include Policy

  ACTIONS = %i[edit delete].freeze

  def initialize(_task_item, membership:, **)
  end

  def edit
    Success()
  end

  def delete
    Success()
  end
end
```

```ruby
# backend/app/policies/expense_participant_policy.rb
# frozen_string_literal: true

class ExpenseParticipantPolicy
  include Policy

  ACTIONS = %i[delete].freeze

  def initialize(_participant, membership:, **)
  end

  def delete
    Success()
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && bundle exec rspec spec/policies/remaining_policies_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add backend/app/policies/ backend/spec/policies/remaining_policies_spec.rb
git commit -m "Add remaining policy classes for all object types"
```

---

### Task 8: ObjectRegistry — Add Policy Field

Extend the registry to map each object type to its policy class.

**Files:**

- Modify: `backend/app/object_registry.rb`
- Test: `backend/spec/object_registry_spec.rb` (create if not exists, or add to existing)

- [ ] **Step 1: Write the failing test**

```ruby
# backend/spec/policies/object_registry_policy_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ObjectRegistry policy field" do
  it "maps every entry with a policy to a valid class" do
    ObjectRegistry::TYPES.each do |entry|
      next unless entry.policy

      policy_class = Object.const_get(entry.policy)
      expect(policy_class).to respond_to(:new), "#{entry.policy} should be a class"
      expect(policy_class.const_get(:ACTIONS)).to be_an(Array), "#{entry.policy} should have ACTIONS"
    end
  end

  it "includes policy for event" do
    expect(ObjectRegistry::BY_KEY["event"].policy).to eq("EventPolicy")
  end

  it "includes policy for settlement" do
    expect(ObjectRegistry::BY_KEY["settlement"].policy).to eq("SettlementPolicy")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && bundle exec rspec spec/policies/object_registry_policy_spec.rb -v`
Expected: FAIL — `Entry` doesn't have `policy` attribute.

- [ ] **Step 3: Add policy field to Entry and all entries**

Modify `backend/app/object_registry.rb`:

Add `policy` to `Entry`:

```ruby
class Entry
  attr_reader :key, :model, :client_type, :pool_method, :tracks_user, :policy

  def initialize(key:, model:, client_type:, pool_method:, tracks_user:, policy: nil)
    @key = key
    @model = model
    @client_type = client_type
    @pool_method = pool_method
    @tracks_user = tracks_user
    @policy = policy
  end
end
```

Update each entry in `TYPES` to include the `policy:` field:

```ruby
TYPES = [
  Entry.new(key: "event", model: "Event", client_type: "event", pool_method: :add_event, tracks_user: true, policy: "EventPolicy"),
  Entry.new(key: "workspace", model: "Workspace", client_type: "workspace", pool_method: :add_workspace, tracks_user: false, policy: "WorkspacePolicy"),
  Entry.new(key: "member", model: "WorkspaceMembership", client_type: "member", pool_method: :add_member, tracks_user: false, policy: "MemberPolicy"),
  Entry.new(key: "date_poll", model: "DatePoll", client_type: "datePoll", pool_method: :add_date_poll, tracks_user: false, policy: "DatePollPolicy"),
  Entry.new(key: "date_range", model: "DateRange", client_type: "dateRange", pool_method: :add_date_range, tracks_user: false, policy: "DateRangePolicy"),
  Entry.new(key: "vote", model: "Vote", client_type: "vote", pool_method: :add_vote, tracks_user: true, policy: "VotePolicy"),
  Entry.new(key: "rsvp", model: "Rsvp", client_type: "rsvp", pool_method: :add_rsvp, tracks_user: true, policy: "RsvpPolicy"),
  Entry.new(key: "task_list", model: "TaskList", client_type: "taskList", pool_method: :add_task_list, tracks_user: true, policy: "TaskListPolicy"),
  Entry.new(key: "task_item", model: "TaskItem", client_type: "taskItem", pool_method: :add_task_item, tracks_user: true, policy: "TaskItemPolicy"),
  Entry.new(key: "expense", model: "Expense", client_type: "expense", pool_method: :add_expense, tracks_user: true, policy: "ExpensePolicy"),
  Entry.new(key: "settlement", model: "Settlement", client_type: "settlement", pool_method: :add_settlement, tracks_user: true, policy: "SettlementPolicy"),
  Entry.new(key: "settlement_transfer", model: "SettlementTransfer", client_type: "settlementTransfer", pool_method: :add_settlement_transfer, tracks_user: false, policy: "SettlementTransferPolicy"),
  Entry.new(key: "chore_roster", model: "ChoreRoster", client_type: "choreRoster", pool_method: :add_chore_roster, tracks_user: true, policy: "ChoreRosterPolicy"),
  Entry.new(key: "chore", model: "Chore", client_type: "chore", pool_method: :add_chore, tracks_user: false, policy: "ChorePolicy"),
  Entry.new(key: "chore_assignment", model: "ChoreAssignment", client_type: "choreAssignment", pool_method: :add_chore_assignment, tracks_user: true, policy: "ChoreAssignmentPolicy"),
  Entry.new(key: "workspace_invite", model: "WorkspaceInvite", client_type: "workspaceInvite", pool_method: :add_workspace_invite, tracks_user: false, policy: "WorkspaceInvitePolicy"),
  Entry.new(key: "expense_participant", model: "ExpenseParticipant", client_type: "expenseParticipant", pool_method: :add_expense_participant, tracks_user: true, policy: "ExpenseParticipantPolicy"),
].freeze
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && bundle exec rspec spec/policies/object_registry_policy_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add backend/app/object_registry.rb backend/spec/policies/object_registry_policy_spec.rb
git commit -m "Add policy field to ObjectRegistry entries"
```

---

### Task 9: PoolSerializer — Attach Permissions

Update PoolSerializer to accept `membership:` and attach `permissions` to every serialized object.

**Files:**

- Modify: `backend/app/serializers/pool_serializer.rb`
- Test: `backend/spec/serializers/pool_serializer_permissions_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# backend/spec/serializers/pool_serializer_permissions_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "PoolSerializer permissions" do
  let(:workspace) { TestFactories.workspace }
  let(:owner) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:owner_membership_row) { TestFactories.workspace_membership(workspace: workspace, user: owner) }
  let(:other_membership_row) { TestFactories.workspace_membership(workspace: workspace, user: other_user) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: owner) }
  let(:event) { Event.find(event_row[:id]) }

  it "includes permissions for event owner" do
    membership = WorkspaceMembership.find(owner_membership_row[:id])
    pool = PoolSerializer.new(membership: membership)
    pool.add_event(event)

    event_obj = pool.to_a.find { |o| o[:objectType] == "event" }
    expect(event_obj[:permissions][:edit]).to eq({ allowed: true })
    expect(event_obj[:permissions][:delete]).to eq({ allowed: true })
  end

  it "includes permissions for non-owner" do
    membership = WorkspaceMembership.find(other_membership_row[:id])
    pool = PoolSerializer.new(membership: membership)
    pool.add_event(event)

    event_obj = pool.to_a.find { |o| o[:objectType] == "event" }
    expect(event_obj[:permissions][:edit]).to eq({ allowed: false, reason: "not_owner" })
  end

  it "omits permissions when no membership provided" do
    pool = PoolSerializer.new(workspace_id: workspace[:id])
    pool.add_event(event)

    event_obj = pool.to_a.find { |o| o[:objectType] == "event" }
    expect(event_obj).not_to have_key(:permissions)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && bundle exec rspec spec/serializers/pool_serializer_permissions_spec.rb -v`
Expected: FAIL — PoolSerializer doesn't accept `membership:` or attach permissions.

- [ ] **Step 3: Update PoolSerializer**

Modify `backend/app/serializers/pool_serializer.rb`:

Change the initializer to accept `membership:` as an optional keyword:

```ruby
def initialize(workspace_id: nil, membership: nil)
  @objects = {}
  @membership = membership
  @workspace_id = if membership
                    membership.workspace_id.to_s
                  else
                    workspace_id&.to_s
                  end
end
```

Add a private helper method to attach permissions:

```ruby
private

def attach_permissions(hash, object)
  return unless @membership

  object_type = hash[:objectType]
  entry = ObjectRegistry::BY_KEY.values.find { |e| e.client_type == object_type }
  return unless entry&.policy

  policy_class = Object.const_get(entry.policy)
  policy = policy_class.new(object, membership: @membership)
  hash[:permissions] = policy.permissions
rescue StandardError => e
  APP_LOGGER.warn { "[PoolSerializer] Failed to compute permissions for #{object_type}: #{e.message}" }
end
```

Then call `attach_permissions(hash, event)` at the end of each `add_*` method, just before assigning to `@objects[key]`. For example, in `add_event`:

```ruby
def add_event(event)
  key = "event:#{event.id}"
  return if @objects.key?(key)

  date_poll = DatePoll.find_by_event(event.id)
  hash = event.to_api_hash(date_poll_id: date_poll&.id&.to_s)
  hash[:rsvpIds] = Rsvp.ids_for_event(event.id)
  attach_permissions(hash, event)
  @objects[key] = hash
end
```

Apply the same pattern to all `add_*` methods and batch methods. For `build_member_hash`, the object is a WorkspaceMembership, so pass the membership to `attach_permissions`. For batch methods like `add_events_batch`, call `attach_permissions` in the loop.

**Special case for `build_member_hash`:** The member being serialized is the target — policies need both the target membership and the acting user's membership. Pass the target membership object:

```ruby
def build_member_hash(user, membership)
  hash = {
    id: membership.id.to_s,
    objectType: "member",
    # ... existing fields ...
  }
  attach_permissions(hash, membership)
  hash
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && bundle exec rspec spec/serializers/pool_serializer_permissions_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Run the full test suite to ensure nothing is broken**

Run: `cd backend && bundle exec rspec -v`
Expected: All existing tests still pass. Some tests create PoolSerializer without `membership:` — these should still work since it's optional.

- [ ] **Step 6: Commit**

```
git add backend/app/serializers/pool_serializer.rb backend/spec/serializers/pool_serializer_permissions_spec.rb
git commit -m "Attach permissions to PoolSerializer output when membership is provided"
```

---

### Task 10: Update Routes to Pass Membership to PoolSerializer

Routes currently create `PoolSerializer.new(workspace_id: ...)`. Update them to pass `membership:` so responses include permissions.

**Files:**

- Modify: `backend/app/routes/events.rb`
- Modify: `backend/app/routes/expenses.rb`
- Modify: `backend/app/routes/settlements.rb`
- Modify: `backend/app/routes/workspaces.rb`
- Modify: `backend/app/routes/chore_rosters.rb`
- Modify: `backend/app/routes/task_lists.rb`
- Modify: `backend/app/routes/invites.rb`
- Modify: `backend/app/app.rb` (add `current_membership` helper)

- [ ] **Step 1: Add `current_membership` helper to App**

The routes already call `member_of_workspace?` which looks up the membership but discards it. Add a helper that caches the membership for the current request.

Modify `backend/app/app.rb`. Replace the `member_of_workspace?` method to also cache the membership, and add a `current_membership` reader:

```ruby
def current_membership(workspace_id = nil)
  return @_current_membership if @_current_membership && workspace_id.nil?
  return nil unless current_user && workspace_id

  @_current_membership = WorkspaceMembership.find_by_workspace_and_user(workspace_id, current_user.id)
end

def member_of_workspace?(workspace_id)
  !current_membership(workspace_id).nil?
end
```

- [ ] **Step 2: Update events.rb**

In `backend/app/routes/events.rb`, after the `member_of_workspace?` check succeeds, the membership is available via `current_membership`. Update PoolSerializer calls:

For GET /api/events (line 21): This iterates workspaces, so the membership changes per workspace. Update to:

```ruby
events.group_by(&:workspace_id).each do |ws_id, ws_events|
  membership = WorkspaceMembership.find_by_workspace_and_user(ws_id, user.id)
  pool = PoolSerializer.new(membership: membership)
  pool.add_all(ws_events, type: :event)
  all_objects.concat(pool.to_a)
end
```

For GET /api/events/:id (line 83): Change to:

```ruby
pool = PoolSerializer.new(membership: current_membership)
```

- [ ] **Step 3: Update expenses.rb**

In `backend/app/routes/expenses.rb`, after `member_of_workspace?` checks:

GET /api/expenses (line 28):

```ruby
pool = PoolSerializer.new(membership: current_membership)
```

- [ ] **Step 4: Update settlements.rb**

In `backend/app/routes/settlements.rb`:

GET /api/settlements (line 29):

```ruby
pool = PoolSerializer.new(membership: current_membership)
```

- [ ] **Step 5: Update workspaces.rb**

In `backend/app/routes/workspaces.rb`:

GET /api/workspaces (line 15) — this lists all workspaces so there's no single membership. Use `workspace_id:` without membership here (no permissions on the list endpoint).

GET /api/workspaces/:id (line 38) — membership is already looked up on line 31:

```ruby
pool = PoolSerializer.new(membership: membership)
```

- [ ] **Step 6: Update chore_rosters.rb, task_lists.rb, invites.rb**

Same pattern — replace `PoolSerializer.new(workspace_id: ...)` with `PoolSerializer.new(membership: current_membership)` after workspace membership has been verified.

- [ ] **Step 7: Run the full backend test suite**

Run: `cd backend && bundle exec rspec`
Expected: All tests pass. Service tests that create their own PoolSerializer still use `workspace_id:` (no membership) — those are fine since permissions are optional.

- [ ] **Step 8: Commit**

```
git add backend/app/app.rb backend/app/routes/
git commit -m "Pass membership to PoolSerializer in all routes for permission serialization"
```

---

### Task 11: Update Services to Use Policies for Enforcement

Replace inline auth checks in services with policy calls. Services receive `membership:` instead of `current_user_id:`.

**Files:**

- Modify: `backend/app/services/events/update.rb`
- Modify: `backend/app/services/events/delete.rb`
- Modify: `backend/app/services/expenses/update.rb`
- Modify: `backend/app/services/expenses/delete.rb`
- Modify: `backend/app/services/settlements/delete.rb`
- Modify: `backend/app/services/date_polls/create.rb`
- Modify: `backend/app/services/date_polls/close.rb`
- Modify: `backend/app/services/date_polls/reopen.rb`
- Modify: `backend/app/services/date_polls/add_date_range.rb`
- Modify: `backend/app/services/date_polls/remove_date_range.rb`
- Modify: `backend/app/services/votes/delete.rb`
- Modify: `backend/app/services/rsvps/delete.rb`
- Modify: `backend/app/services/members/update_role.rb`
- Modify: `backend/app/services/settlements/mark_paid.rb`
- Modify: Corresponding route files to pass `membership:` instead of `current_user_id:`
- Modify: All affected service specs

**This is a large task. It should be split into sub-steps per service domain.**

- [ ] **Step 1: Events::Delete — update service**

Replace `Event.authorize_owner` with `EventPolicy`:

```ruby
# backend/app/services/events/delete.rb
module Events
  module Delete
    class << self
      include Dry::Monads[:result]

      def call(event_id:, membership:)
        Event.find_result(event_id)
             .bind { |event| authorize(event, membership) }
             .bind { |event| delete_event(event) }
      end

      private

      def authorize(event, membership)
        EventPolicy.new(event, membership: membership)
                   .delete
                   .bind { Success(event) }
                   .or { |reason| Failure(ServiceError.forbidden(reason.to_s)) }
      end

      # delete_event method stays unchanged
    end
  end
end
```

- [ ] **Step 2: Update Events::Delete route call**

In `backend/app/routes/events.rb` line 108, change:

```ruby
result = Events::Delete.call(event_id: event.id, membership: current_membership)
```

- [ ] **Step 3: Update Events::Delete spec**

In `backend/spec/services/events/delete_spec.rb`, change `current_user_id:` to `membership:`:

```ruby
RSpec.describe Events::Delete do
  let(:workspace) { TestFactories.workspace }

  it "returns failure when user is not the owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    TestFactories.workspace_membership(workspace: workspace, user: owner)
    other_membership = TestFactories.workspace_membership(workspace: workspace, user: other_user)
    event = TestFactories.event(workspace: workspace, user: owner)
    membership = WorkspaceMembership.find(other_membership[:id])

    result = described_class.call(event_id: event[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to include("not_owner")
    expect(DB[:events].where(id: event[:id]).count).to eq(1)
  end

  it "deletes event when user is owner" do
    user = TestFactories.user
    owner_membership = TestFactories.workspace_membership(workspace: workspace, user: user)
    event = TestFactories.event(workspace: workspace, user: user)
    membership = WorkspaceMembership.find(owner_membership[:id])

    result = described_class.call(event_id: event[:id], membership: membership)

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "event", id: event[:id] }])
    expect(DB[:events].where(id: event[:id]).count).to eq(0)
  end
end
```

- [ ] **Step 4: Run Events::Delete spec**

Run: `cd backend && bundle exec rspec spec/services/events/delete_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Apply the same pattern to Events::Update**

Replace `Event.authorize_owner(event, current_user_id)` on line 23 with:

```ruby
.bind { |event| EventPolicy.new(event, membership: membership).edit.bind { Success(event) }.or { |r| Failure(ServiceError.forbidden(r.to_s)) } }
```

Change the method signature from `current_user_id:` to `membership:`. Update the route and spec correspondingly.

- [ ] **Step 6: Apply the same pattern to Expenses::Update and Expenses::Delete**

Replace `check_owner` and `check_not_settled` with `ExpensePolicy`:

```ruby
def authorize(expense, membership)
  ExpensePolicy.new(expense, membership: membership)
               .edit  # or .delete
               .bind { Success(expense) }
               .or { |reason| Failure(ServiceError.forbidden(reason.to_s)) }
end
```

Remove the `Expenses::Validators` module (or keep `check_not_settled` if it's still used for non-policy validation — but since the policy now checks settlement state, it can be removed from the service auth chain).

Update routes to pass `membership:` instead of `current_user_id:`.
Update specs.

- [ ] **Step 7: Apply to Settlements::Delete**

Replace the inline `authorize` method with `SettlementPolicy`:

```ruby
def authorize(settlement, membership)
  SettlementPolicy.new(settlement, membership: membership)
                  .delete
                  .bind { Success(settlement) }
                  .or { |reason| Failure(ServiceError.forbidden(reason.to_s)) }
end
```

Change signature from `current_user_id:` to `membership:`. Update route and spec.

- [ ] **Step 8: Apply to Settlements::MarkPaid**

Move the recipient check from the route (settlements.rb:108) into the service using `SettlementTransferPolicy`:

```ruby
def call(transfer_id:, paid:, membership:, workspace_id:)
  SettlementTransfer.find_result(transfer_id)
                    .bind { |transfer| authorize(transfer, membership) }
                    .bind { |transfer| update_paid(transfer, paid, workspace_id) }
end

def authorize(transfer, membership)
  SettlementTransferPolicy.new(transfer, membership: membership)
                          .mark_paid
                          .bind { Success(transfer) }
                          .or { |reason| Failure(ServiceError.forbidden(reason.to_s)) }
end
```

Remove the inline check from `backend/app/routes/settlements.rb` lines 108-111.

- [ ] **Step 9: Apply to DatePolls::Create, Close, Reopen, AddDateRange, RemoveDateRange**

All use `Event.authorize_owner(event, current_user_id)`. Replace with `EventPolicy` (for create) or `DatePollPolicy` (for close/reopen/add_date_range/remove_date_range):

```ruby
# DatePolls::Create — uses EventPolicy#create_poll
EventPolicy.new(event, membership: membership)
           .create_poll
           .bind { Success(event) }
           .or { |reason| Failure(ServiceError.forbidden(reason.to_s)) }
```

Change all signatures from `current_user_id:` to `membership:`. Update routes and specs.

- [ ] **Step 10: Apply to Votes::Delete and Rsvps::Delete**

Replace inline `authorize_owner` with `VotePolicy` and `RsvpPolicy`. Change `user_id:` to `membership:`. Update routes and specs.

- [ ] **Step 11: Apply to Members::UpdateRole**

Replace the inline role-based auth logic (lines 41-52) with `MemberPolicy`:

```ruby
def perform(membership, target_membership, new_role)
  MemberPolicy.new(target_membership, membership: membership)
              .change_role
              .bind { do_update(target_membership, new_role) }
              .or { |reason| Failure(ServiceError.forbidden(reason.to_s)) }
end
```

Change `acting_user_id:` to `membership:` (the route will need to look up the acting user's membership). Update route and spec.

- [ ] **Step 12: Remove Event.authorize_owner**

Delete the `authorize_owner` class method from `backend/app/models/event.rb` (lines 74-80). It's no longer used.

- [ ] **Step 13: Remove Expenses::Validators if no longer needed**

If `check_not_settled` and `check_owner` are no longer called from any service, delete `backend/app/services/expenses/validators.rb`.

- [ ] **Step 14: Remove require_admin_or_owner! from app.rb**

The invites route uses `require_admin_or_owner!` — replace with policy check in the route or service. Then remove the helper from app.rb.

- [ ] **Step 15: Run the full backend test suite**

Run: `cd backend && bundle exec rspec`
Expected: All tests pass.

- [ ] **Step 16: Commit**

```
git add backend/
git commit -m "Replace inline auth checks with policy enforcement in all services"
```

---

### Task 12: WebSocket — Attach Per-User Permissions to Broadcasts

Update Listener and ConnectionManager so that broadcasts include per-user permissions.

**Files:**

- Modify: `backend/app/websocket/listener.rb`
- Modify: `backend/app/websocket/connection_manager.rb`
- Modify: `backend/app/websocket/message_handler.rb` (store membership on connection)

- [ ] **Step 1: Store membership on WebSocket connections**

In `backend/app/websocket/connection_manager.rb`, update `Connection` to store the workspace membership:

Add `attr_accessor :membership` to the Connection class (alongside `workspace_ids`).

In `backend/app/websocket/message_handler.rb`, when `switch_workspace` succeeds (the membership is already looked up on line 48), store it on the connection:

```ruby
def switch_workspace(connection, connection_id, user_id, workspace_id, since = nil)
  # ... existing validation ...
  membership = WorkspaceMembership.find_by_workspace_and_user(workspace_id, user_id)
  # ... existing check ...
  Websocket::ConnectionManager.instance.set_workspaces(connection_id, [workspace_id.to_s])
  Websocket::ConnectionManager.instance.set_membership(connection_id, membership)
  # ... existing sync ...
end
```

Add `set_membership` to ConnectionManager:

```ruby
def set_membership(connection_id, membership)
  @mutex.synchronize do
    connection = @connections[connection_id]
    connection&.membership = membership
  end
end
```

- [ ] **Step 2: Update Sync::WorkspaceSync to accept membership**

Modify `backend/app/services/sync/workspace_sync.rb` to accept an optional `membership:` and pass it to PoolSerializer:

```ruby
def call(workspace_id:, since: nil, membership: nil)
  # ... existing logic ...
  pool = if membership
           PoolSerializer.new(membership: membership)
         else
           PoolSerializer.new(workspace_id: workspace_id)
         end
  # ... rest unchanged ...
end
```

Update the message_handler switch_workspace call:

```ruby
result = Sync::WorkspaceSync.call(workspace_id: workspace_id, since: since_time, membership: membership)
```

- [ ] **Step 3: Pre-fetch context in Listener, attach permissions in ConnectionManager**

In `backend/app/websocket/listener.rb`, when handling an "update" notification, pass the raw object data alongside the serialized pool:

```ruby
when "update"
  object = find_object(object_type, object_id)
  if object
    pool = PoolSerializer.new(workspace_id: workspace_id)
    pool.send(config.pool_method, object)
    message[:data] = { objects: pool.to_a }
    message[:_raw_objects] = { object_type => object }  # For permission computation

    # Pre-fetch context needed by policies (e.g., parent event for settlements)
    message[:_context] = prefetch_context(config, object)
  else
    # ... existing delete handling ...
  end
```

Add a `prefetch_context` method:

```ruby
def prefetch_context(config, object)
  context = {}
  case config.key
  when "settlement", "settlement_transfer"
    settlement = config.key == "settlement" ? object : Settlement.find(object.settlement_id)
    context[:event] = Event.find(settlement.event_id) if settlement
  when "date_poll", "date_range"
    if config.key == "date_poll"
      context[:event] = Event.find(object.event_id)
    else
      poll = DatePoll.find(object.date_poll_id)
      context[:event] = Event.find(poll.event_id) if poll
    end
  end
  context
end
```

In `backend/app/websocket/connection_manager.rb`, update `broadcast_to_workspace` to attach per-user permissions:

```ruby
def broadcast_to_workspace(workspace_id, message)
  connection_ids = @mutex.synchronize { (@workspace_connections[workspace_id] || Set.new).to_a }

  has_objects = message.dig(:data, :objects)&.any?
  raw_objects = message.delete(:_raw_objects) || {}
  context = message.delete(:_context) || {}

  if has_objects
    connection_ids.each do |connection_id|
      connection = @mutex.synchronize { @connections[connection_id] }
      next unless connection

      personalized = attach_permissions(message, connection.membership, raw_objects, context)
      send_to_connection(connection, connection_id, personalized, workspace_id)
    end
  else
    json_message = message.to_json
    connection_ids.each do |connection_id|
      connection = @mutex.synchronize { @connections[connection_id] }
      next unless connection
      send_raw(connection, connection_id, json_message, workspace_id)
    end
  end
end

private

def attach_permissions(message, membership, raw_objects, context)
  return message unless membership

  objects = message[:data][:objects].map do |obj|
    object_type_key = ObjectRegistry::TYPES.find { |e| e.client_type == obj[:objectType] }&.key
    entry = ObjectRegistry::BY_KEY[object_type_key]
    next obj unless entry&.policy

    raw_object = raw_objects[entry.key]
    next obj unless raw_object

    policy_class = Object.const_get(entry.policy)
    policy = policy_class.new(raw_object, membership: membership, **context)
    obj.merge(permissions: policy.permissions)
  end

  message.merge(data: message[:data].merge(objects: objects))
end

def send_to_connection(connection, connection_id, message, workspace_id)
  connection.websocket.write(message.to_json)
  connection.websocket.flush
rescue StandardError => e
  APP_LOGGER.error { "[ConnectionManager] Error broadcasting to workspace #{workspace_id}, conn #{connection_id}: #{e.class}: #{e.message}" }
  unregister(connection_id)
end

def send_raw(connection, connection_id, json_message, workspace_id)
  connection.websocket.write(json_message)
  connection.websocket.flush
rescue StandardError => e
  APP_LOGGER.error { "[ConnectionManager] Error broadcasting to workspace #{workspace_id}, conn #{connection_id}: #{e.class}: #{e.message}" }
  unregister(connection_id)
end
```

- [ ] **Step 4: Run the full backend test suite**

Run: `cd backend && bundle exec rspec`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```
git add backend/app/websocket/ backend/app/services/sync/workspace_sync.rb
git commit -m "Attach per-user permissions to WebSocket broadcasts and sync responses"
```

---

### Task 13: Frontend Types — Add Permission Type

Update the TypeScript pool types to include `permissions`.

**Files:**

- Modify: `frontend/src/types/pool.ts`

- [ ] **Step 1: Add Permission interface and update PoolObjectBase**

In `frontend/src/types/pool.ts`, add before `PoolObjectBase`:

```typescript
export interface Permission {
  allowed: boolean
  reason?: string
}
```

Update `PoolObjectBase`:

```typescript
interface PoolObjectBase<T extends string> {
  id: string
  objectType: T
  updatedAt: string
  permissions?: Record<string, Permission | string[]>
}
```

- [ ] **Step 2: Run typecheck**

Run: `cd frontend && pnpm exec vue-tsc --noEmit`
Expected: PASS — the new field is optional so existing code compiles.

- [ ] **Step 3: Commit**

```
git add frontend/src/types/pool.ts
git commit -m "Add Permission type and permissions field to pool objects"
```

---

### Task 14: Frontend — Add usePermission Composable

A small helper composable that extracts permissions from pool objects with safe defaults.

**Files:**

- Create: `frontend/src/composables/usePermission.ts`
- Test: `frontend/src/composables/usePermission.spec.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// frontend/src/composables/usePermission.spec.ts
import { describe, it, expect } from 'vitest'
import { ref, computed } from 'vue'
import { can, permissionReason } from './usePermission'
import type { Permission } from '@/types/pool'

describe('usePermission', () => {
  describe('can', () => {
    it('returns true when permission is allowed', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: true },
      }
      expect(can(permissions, 'edit')).toBe(true)
    })

    it('returns false when permission is denied', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: false, reason: 'not_owner' },
      }
      expect(can(permissions, 'edit')).toBe(false)
    })

    it('returns false when permission key is missing', () => {
      const permissions: Record<string, Permission> = {}
      expect(can(permissions, 'edit')).toBe(false)
    })

    it('returns false when permissions is undefined', () => {
      expect(can(undefined, 'edit')).toBe(false)
    })
  })

  describe('permissionReason', () => {
    it('returns the reason when denied', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: false, reason: 'not_owner' },
      }
      expect(permissionReason(permissions, 'edit')).toBe('not_owner')
    })

    it('returns undefined when allowed', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: true },
      }
      expect(permissionReason(permissions, 'edit')).toBeUndefined()
    })

    it('returns undefined when missing', () => {
      expect(permissionReason(undefined, 'edit')).toBeUndefined()
    })
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && pnpm exec vitest run src/composables/usePermission.spec.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the composable**

```typescript
// frontend/src/composables/usePermission.ts
import type { Permission } from '@/types/pool'

type Permissions = Record<string, Permission | string[]> | undefined

export function can(permissions: Permissions, action: string): boolean {
  if (!permissions) return false
  const perm = permissions[action]
  if (!perm || Array.isArray(perm)) return false
  return perm.allowed
}

export function permissionReason(
  permissions: Permissions,
  action: string
): string | undefined {
  if (!permissions) return undefined
  const perm = permissions[action]
  if (!perm || Array.isArray(perm)) return undefined
  return perm.reason
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && pnpm exec vitest run src/composables/usePermission.spec.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add frontend/src/composables/usePermission.ts frontend/src/composables/usePermission.spec.ts
git commit -m "Add usePermission composable for reading pool object permissions"
```

---

### Task 15: Frontend — Migrate Components to Use Permissions

Replace all inline permission checks in Vue components with reads from `permissions`.

**Files:**

- Modify: `frontend/src/pages/EventPage.vue`
- Modify: `frontend/src/pages/EventPlanningPage.vue`
- Modify: `frontend/src/pages/EventPlanningDateRangesPage.vue`
- Modify: `frontend/src/components/expenses/ExpenseRow.vue`
- Modify: `frontend/src/components/expenses/SettlementSection.vue`
- Modify: `frontend/src/pages/MembersPage.vue`
- Modify: `frontend/src/components/events/RsvpSection.vue`
- Modify: `frontend/src/components/events/DatePollSection.vue`

- [ ] **Step 1: Migrate EventPage.vue**

Replace:

```typescript
const isOwner = computed(() => currentUserId.value === event.value?.userId)
```

With:

```typescript
import { can } from '@/composables/usePermission'

const canEdit = computed(() => can(event.value?.permissions, 'edit'))
const canDelete = computed(() => can(event.value?.permissions, 'delete'))
```

Update template references from `isOwner` to `canEdit`/`canDelete`.

- [ ] **Step 2: Migrate EventPlanningPage.vue**

Replace:

```typescript
const isOwner = computed(() => currentUserId.value === event.value?.userId)
const canOpenOrReopenPoll = computed(
  () => isOwner.value && !!event.value && !eventHasStarted.value
)
```

With:

```typescript
import { can } from '@/composables/usePermission'

const canCreatePoll = computed(() =>
  can(event.value?.permissions, 'createPoll')
)
```

Update template references.

- [ ] **Step 3: Migrate EventPlanningDateRangesPage.vue**

Replace `isOwner` with `can(event.value?.permissions, 'createPoll')` (or the appropriate action for date range management — which is on the parent event as `createPoll`, since date ranges belong to polls owned by the event owner).

- [ ] **Step 4: Migrate ExpenseRow.vue**

Replace:

```typescript
const isOwner = computed(() => props.expense.userId === props.currentUserId)
const isSettled = computed(() => !!props.expense.settlementId)
```

With:

```typescript
import { can, permissionReason } from '@/composables/usePermission'

const canEdit = computed(() => can(props.expense.permissions, 'edit'))
const canDelete = computed(() => can(props.expense.permissions, 'delete'))
```

The `settled` reason is now available via `permissionReason(props.expense.permissions, 'edit')` for tooltip display.

- [ ] **Step 5: Migrate SettlementSection.vue**

Replace:

```typescript
function canDeleteSettlement(settlementUserId: string | null): boolean { ... }
function canMarkPaid(toUserId: string | null): boolean { ... }
```

With reads from the settlement and transfer objects' permissions:

```typescript
import { can } from '@/composables/usePermission'

// For settlement delete button:
can(settlement.permissions, 'delete')

// For transfer mark-paid button:
can(transfer.permissions, 'markPaid')
```

- [ ] **Step 6: Migrate MembersPage.vue**

Replace:

```typescript
function canChangeRole(member: PoolMember): boolean { ... }
function availableRolesFor(): string[] { ... }
```

With:

```typescript
import { can } from '@/composables/usePermission'

function canChangeRole(member: PoolMember): boolean {
  return can(member.permissions, 'changeRole')
}

function availableRolesFor(member: PoolMember): string[] {
  const roles = member.permissions?.availableRoles
  return Array.isArray(roles) ? roles : []
}
```

- [ ] **Step 7: Migrate RsvpSection.vue**

Replace direct `userId === currentUserId` checks with `can(rsvp.permissions, 'delete')`.

- [ ] **Step 8: Migrate DatePollSection.vue**

Replace the `isOwner` prop with reads from the event's permissions. The parent component should pass the event object (which now carries permissions) instead of a boolean `isOwner` prop.

- [ ] **Step 9: Run typecheck**

Run: `cd frontend && pnpm exec vue-tsc --noEmit`
Expected: PASS.

- [ ] **Step 10: Run frontend tests**

Run: `cd frontend && pnpm exec vitest run`
Expected: PASS (update test fixtures to include `permissions` where needed).

- [ ] **Step 11: Commit**

```
git add frontend/src/
git commit -m "Migrate all frontend components to read permissions from pool objects"
```

---

### Task 16: Run Full CI

Verify everything works together.

- [ ] **Step 1: Run backend tests**

Run: `cd backend && bundle exec rspec`
Expected: All pass.

- [ ] **Step 2: Run frontend checks**

Run: `mise run check`
Expected: Lint, typecheck, and tests all pass.

- [ ] **Step 3: Run E2E tests**

Run: `mise run e2e`
Expected: All pass (E2E tests exercise the full stack so permissions flow end-to-end).

- [ ] **Step 4: Commit any fixes needed**

If any tests needed fixing, commit the fixes.
