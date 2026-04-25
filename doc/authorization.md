# Authorization

Policy classes are the single source of truth for all permissions. The backend
enforces them, serializes them onto every pool object, and the frontend reads
them — it never computes permissions from user IDs.

## How it works

1. **Policy classes** (`backend/app/policies/`) define what actions are allowed.
   Each policy includes the `Policy` module, declares an `ACTIONS` array, and
   implements a method per action that returns `Success()` or `Failure(:reason)`.

2. **Services** call `SomePolicy.enforce(:action, subject, membership: m)` which
   returns `Success(subject)` or `Failure(ServiceError.forbidden("reason"))`.
   This is the enforcement point — every mutating endpoint goes through it.

3. **PoolSerializer** attaches `permissions: { action: { allowed: true/false, reason: "..." } }`
   to every serialized object when a `membership:` is provided.

4. **WebSocket broadcasts** compute per-user permissions for each connected client
   via `Websocket::PolicyContext`.

5. **Frontend** reads permissions with `can(obj.permissions, 'action')` and
   `permissionUx(obj.permissions, 'action')` — never checks user IDs directly.

## Adding a new policy action

1. Add the action symbol to the policy's `ACTIONS` array
2. Implement the method (return `Success()` or `Failure(:reason)`)
3. Call `Policy.enforce(:action, ...)` in the service
4. If the reason is new, add it to `usePermission.ts`:
   - `HIDE_REASONS` — user can never do this (wrong role/owner)
   - `DISABLE_REASONS` — user could do this but something temporary blocks them
   - `MODAL_REASONS` — needs a longer explanation
   - Unknown reasons fall back to disabled + raw reason as tooltip

## Adding a new policy class

1. Create `backend/app/policies/foo_policy.rb` — include `Policy`, define `ACTIONS`
2. Add `policy: "FooPolicy"` to the ObjectRegistry entry
3. The `app/policies/` directory is a Zeitwerk push_dir, so no require needed

## Policy conventions

- `Success()` — action allowed
- `Failure(:not_owner)` — wrong person (event-level ownership)
- `Failure(:not_creator)` — wrong person (object-level creator)
- `Failure(:not_event_owner)` — wrong person (checked via parent event)
- `Failure(:not_admin_or_owner)` — wrong workspace role
- `Failure(:settled)` — temporary state blocker
- `Failure(:has_expenses)` — temporary state blocker
- `Failure(:not_recipient)` / `Failure(:not_sender)` — transfer-specific

Policies take the subject as the first positional arg and `membership:` as a
keyword. Extra context (e.g., `event:`, `has_expenses:`) can be passed as
keywords — the `**` splat in initializers accepts them.

## Context passing for performance

Some policies need data that would cause N+1 queries if fetched per-object
(e.g., EventPolicy needs to know if an event has expenses). Pass this as a
keyword to avoid the query inside the policy:

```ruby
# In PoolSerializer — batch query, then pass result
events_with_expenses = DB[:expenses].where(event_id: ids).distinct.select_map(:event_id).to_set
attach_permissions(hash, event, has_expenses: events_with_expenses.include?(event.id.to_s))

# In service — single query is fine
EventPolicy.enforce(:delete, event, membership: m, has_expenses: DB[:expenses].where(event_id: event.id).any?)
```

## Frontend UX patterns

`permissionUx(permissions, action)` returns one of:

| Behavior                            | When                    | Implementation                        |
| ----------------------------------- | ----------------------- | ------------------------------------- |
| `{ behavior: 'enabled' }`           | Action allowed          | Normal button                         |
| `{ behavior: 'hidden' }`            | Role/ownership mismatch | `v-if` hides element                  |
| `{ behavior: 'disabled', tooltip }` | Temporary blocker       | Button disabled, `title` shows reason |
| `{ behavior: 'modal', message }`    | Needs explanation       | Button opens modal with message       |

Unknown reasons fall back to `disabled` with the raw reason string as tooltip.
