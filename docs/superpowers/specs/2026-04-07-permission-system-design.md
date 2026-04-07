# Permission System Design

## Problem

Permission and ability checks are scattered across ~20 files with duplicated logic between the Ruby backend (inline checks in services and routes) and Vue frontend (computed properties in components). There is no mechanism preventing drift between the two — the same rule is expressed independently in both codebases.

## Approach

**Backend is the single source of truth.** Policy classes compute permissions per object per user. The serialized permissions are sent alongside every object in the pool as a nested `permissions` hash. The frontend reads these flags — it never computes permissions itself.

## Backend

### Policy Module

A shared `Policy` module in `app/policies/policy.rb` provides the `permissions` method and Result-to-hash conversion. All policy classes include it.

```ruby
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
    in Success then { allowed: true }
    in Failure(reason) then { allowed: false, reason: reason.to_s }
    end
  end
end
```

Each policy action returns a `Result` monad — `Success()` when allowed, `Failure(:reason)` when not. Reasons are snake_case symbols (e.g., `:not_owner`, `:has_settlements`) that the frontend maps to user-facing copy.

`ACTIONS` is a constant array of symbols declaring every action the policy covers. It serves as both the iteration source for `permissions` and as at-a-glance documentation.

### Policy Classes

One class per object type in `app/policies/`. Each takes the object as the first argument and `membership:` as a keyword (which carries `user_id`, `workspace_id`, and `role`).

Optional keyword arguments provide pre-fetched related objects. When omitted, the policy fetches them itself. This lets the WebSocket layer pre-fetch once per broadcast while HTTP callers can just pass `membership:` and let the policy handle the rest.

```ruby
class EventPolicy
  include Policy

  ACTIONS = %i[edit delete create_poll create_expense create_settlement
               create_rsvp create_chore_roster create_task_list].freeze

  def initialize(event, membership:, **)
    @event = event
    @owner = event.user_id == membership.user_id
  end

  def edit
    return Failure(:not_owner) unless @owner
    Success()
  end

  def delete
    return Failure(:not_owner) unless @owner
    Success()
  end

  def create_poll
    return Failure(:not_owner) unless @owner
    Success()
  end

  # ... other actions follow the same pattern
end
```

```ruby
class SettlementPolicy
  include Policy

  ACTIONS = %i[delete].freeze

  def initialize(settlement, membership:, event: nil, **)
    @settlement = settlement
    @membership = membership
    @event = event || Event.find(settlement.event_id)
    @creator = settlement.user_id == membership.user_id
    @event_owner = @event&.user_id == membership.user_id
  end

  def delete
    return Failure(:not_creator_or_event_owner) unless @creator || @event_owner
    Success()
  end
end
```

```ruby
class MemberPolicy
  include Policy

  ACTIONS = %i[change_role].freeze

  def initialize(member, membership:, **)
    @member = member
    @membership = membership
    @role = membership.role
    @self = member.user_id == membership.user_id
  end

  def change_role
    return Failure(:cannot_change_own_role) if @self
    return Failure(:not_admin_or_owner) unless %w[admin owner].include?(@role)
    return Failure(:cannot_change_owner) if @member.role == "owner" && @role != "owner"
    Success()
  end

  # Non-boolean permission: which roles the current user can assign to this member
  def available_roles
    return [] if change_role.failure?

    case @role
    when "owner" then %w[member admin owner]
    when "admin" then %w[member admin]
    else []
    end
  end

  def permissions
    super.merge(availableRoles: available_roles)
  end
end
```

### Full Policy List

Every object type that has POST/PUT/DELETE endpoints gets a policy. Parent objects carry child-creation permissions.

| Policy                     | Actions                                                                                                                          |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `WorkspacePolicy`          | `create_event`, `invite`, `manage_members`                                                                                       |
| `EventPolicy`              | `edit`, `delete`, `create_poll`, `create_expense`, `create_settlement`, `create_rsvp`, `create_chore_roster`, `create_task_list` |
| `ExpensePolicy`            | `edit`, `delete`                                                                                                                 |
| `ExpenseParticipantPolicy` | `delete`                                                                                                                         |
| `SettlementPolicy`         | `delete`                                                                                                                         |
| `SettlementTransferPolicy` | `mark_paid`                                                                                                                      |
| `DatePollPolicy`           | `close`, `reopen`, `create_date_range`                                                                                           |
| `DateRangePolicy`          | `delete`, `create_vote`                                                                                                          |
| `VotePolicy`               | `delete`                                                                                                                         |
| `RsvpPolicy`               | `delete`                                                                                                                         |
| `ChoreRosterPolicy`        | `edit`, `delete`, `create_chore`                                                                                                 |
| `ChorePolicy`              | `edit`, `delete`                                                                                                                 |
| `ChoreAssignmentPolicy`    | `edit`, `delete`                                                                                                                 |
| `TaskListPolicy`           | `edit`, `delete`, `create_task_item`                                                                                             |
| `TaskItemPolicy`           | `edit`, `delete`                                                                                                                 |
| `WorkspaceInvitePolicy`    | `delete`, `remind`                                                                                                               |
| `MemberPolicy`             | `change_role` (+ `availableRoles`)                                                                                               |

### ObjectRegistry Extension

Add a `policy` field to registry entries so policies can be resolved generically:

```ruby
Entry.new(
  key: "event",
  model: "Event",
  client_type: "event",
  pool_method: :add_event,
  tracks_user: true,
  policy: "EventPolicy"
)
```

### PoolSerializer Integration

PoolSerializer takes `membership:` and attaches permissions when serializing each object. The existing `workspace_id` is derived from `membership.workspace_id`:

```ruby
class PoolSerializer
  def initialize(membership:)
    @objects = {}
    @membership = membership
    @workspace_id = membership.workspace_id.to_s
  end

  def add_event(event)
    key = "event:#{event.id}"
    return if @objects.key?(key)

    date_poll = DatePoll.find_by_event(event.id)
    hash = event.to_api_hash(date_poll_id: date_poll&.id&.to_s)
    hash[:rsvpIds] = Rsvp.ids_for_event(event.id)
    hash[:permissions] = EventPolicy.new(event, membership: @membership).permissions
    @objects[key] = hash
  end

  # ... same pattern for all add_* methods
end
```

### Service Enforcement

Services call the policy directly instead of inline auth checks. The policy returns a Result monad, so it chains naturally with `bind`:

```ruby
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
    end
  end
end
```

The `delete` method on the policy is the single piece of code that decides both "can this user delete?" for enforcement and "show the delete button?" for the frontend.

### WebSocket Broadcasts

The Listener serializes object data once without permissions (as today). ConnectionManager attaches per-user permissions before sending to each connection:

1. Listener fetches the object and serializes it (one DB query, one serialization)
2. Listener pre-fetches any related objects policies might need (e.g., the parent event for a settlement) — one extra query at most
3. ConnectionManager, for each connection in the workspace, instantiates the policy with the connection's membership and the pre-fetched context, then merges `permissions` into the object hash
4. Each connection receives the same object data with different permission values

Policy evaluation is cheap (boolean logic on pre-fetched data), so the per-connection cost is negligible. The expensive work (DB queries, serialization) happens once.

The pre-fetched context is passed as keyword arguments to the policy constructor. The ObjectRegistry's `policy` field lets ConnectionManager resolve the right policy class generically.

## Frontend

### Type Changes

Add a `Permission` type and an optional `permissions` field to `PoolObjectBase`:

```typescript
export interface Permission {
  allowed: boolean
  reason?: string
}

interface PoolObjectBase<T extends string> {
  id: string
  objectType: T
  updatedAt: string
  permissions?: Record<string, Permission | string[]>
}
```

`Record<string, Permission | string[]>` covers boolean permissions and `availableRoles` on members.

### Component Migration

Replace all inline permission checks with reads from `permissions`:

```typescript
// Before
const isOwner = computed(() => currentUserId.value === event.value?.userId)
const canEdit = isOwner

// After
const canEdit = computed(() => event.value?.permissions?.edit?.allowed ?? false)
const editReason = computed(() => event.value?.permissions?.edit?.reason)
```

Disabled buttons can show the reason as a tooltip:

```vue
<button
  :disabled="!canDelete.allowed"
  :title="canDelete.reason ? t(`permissions.${canDelete.reason}`) : undefined"
  @click="handleDelete"
>
  Delete
</button>
```

Reasons are i18n keys — the frontend maps them to localized strings.

### Files to Change

Every component that currently has an `isOwner` computed or inline `userId === currentUserId` check:

- `EventPage.vue` — `isOwner` -> `permissions.edit`, `permissions.delete`
- `EventPlanningPage.vue` — `isOwner`, `canOpenOrReopenPoll` -> `permissions.createPoll`
- `EventPlanningDateRangesPage.vue` — `isOwner` -> parent event permissions
- `ExpenseRow.vue` — `isOwner` -> `permissions.edit`, `permissions.delete`
- `SettlementSection.vue` — `canDeleteSettlement`, `canMarkPaid` -> `permissions.delete`, `permissions.markPaid`
- `MembersPage.vue` — `canChangeRole`, `availableRolesFor` -> `permissions.changeRole`, `permissions.availableRoles`
- `RsvpSection.vue` — `userId === currentUserId` -> `permissions.delete`
- `DatePollSection.vue` — `isOwner` prop -> parent event permissions

## Testing

Each policy class gets its own spec file testing every action with different user/role combinations. Since policies are plain Ruby objects with no framework dependencies, these are fast unit tests:

```ruby
RSpec.describe EventPolicy do
  let(:event) { Event.new(id: "1", user_id: "owner-id", ...) }
  let(:owner_membership) { WorkspaceMembership.new(user_id: "owner-id", role: "member", ...) }
  let(:other_membership) { WorkspaceMembership.new(user_id: "other-id", role: "member", ...) }

  describe "#delete" do
    it "allows the event owner" do
      policy = EventPolicy.new(event, membership: owner_membership)
      expect(policy.delete).to be_success
    end

    it "rejects non-owners" do
      policy = EventPolicy.new(event, membership: other_membership)
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:not_owner)
    end
  end
end
```

Existing service specs continue to test the full flow (route -> service -> policy -> DB), but permission logic is no longer duplicated in service specs.

Frontend components no longer need to test permission logic — they just check that buttons appear/disappear based on the `permissions` field in test fixtures.
