# Workspaces

Workspaces are the top-level organizational unit in Tayaway. All domain data (events, polls, votes) belongs to a workspace. Users can be members of multiple workspaces but interact with one at a time.

## Data Model

```
┌──────────────┐       ┌──────────────────────┐       ┌──────────────┐
│   Workspace  │◄──────│ WorkspaceMembership  │──────►│     User     │
│              │       │ (role: owner/admin/  │       │              │
│   name       │       │        member)       │       │   email      │
└──────┬───────┘       └──────────────────────┘       │   name       │
       │                                              └──────────────┘
       │ has many
       ▼
┌──────────────┐
│    Event     │
│              │──► DatePoll ──► DateRange ──► Vote
└──────────────┘
```

- **Workspace** has a name and many memberships.
- **WorkspaceMembership** is the join between a workspace and a user, with a `role` (owner, admin, or member).
- **Event** (and everything beneath it) belongs to a single workspace via `workspace_id`.

## Authorization

All workspace-scoped API routes verify the current user is a member of the workspace before proceeding. The WebSocket `switch_workspace` message also validates membership before subscribing the connection.

## Workspace Switching (Frontend)

The frontend keeps one workspace active at a time, persisted in `localStorage`.

```
User clicks workspace in nav
        │
        ▼
workspaceStore.switchWorkspace(id)
  1. Update currentWorkspaceId + localStorage
  2. Clear object pool (keep workspace objects for the selector)
        │
        ▼
wsStore.sendSwitchWorkspace(id)
  3. Set hasSynced = false (shows loading state)
  4. Send switch_workspace message to server
        │
        ▼
Server validates membership, sends sync response
  5. Pool imports new workspace's objects (events, members, etc.)
  6. hasSynced = true → UI renders
```

Key stores involved:

- **workspace store** — tracks `currentWorkspaceId`, exposes `allWorkspaces` / `currentWorkspace`
- **objectPool store** — holds all cached objects; `clearExcept('workspace')` on switch keeps the selector working while flushing stale data
- **websocket store** — sends `switch_workspace`, handles `sync` response

## Workspace Switching (Backend)

When the server receives a `switch_workspace` WebSocket message:

1. Validates the user is a member of the target workspace
2. Updates the ConnectionManager to associate the connection with the new workspace
3. Serializes the full workspace data (workspace, memberships, users, events, polls, votes) via `PoolSerializer`
4. Sends a `sync` message back to the client

After switching, the ConnectionManager only delivers real-time broadcasts for the active workspace to that connection.

## Workspace Creation

Workspaces are created during user signup — each new user gets a personal workspace where they are the owner. There is no self-service workspace creation UI yet.

## Key Files

| Area               | Path                                          |
| ------------------ | --------------------------------------------- |
| Backend model      | `backend/app/models/workspace.rb`             |
| Membership model   | `backend/app/models/workspace_membership.rb`  |
| API routes         | `backend/app/routes/workspaces.rb`            |
| WebSocket handler  | `backend/app/routes/ws.rb`                    |
| Connection manager | `backend/app/websocket/connection_manager.rb` |
| Frontend store     | `frontend/src/stores/workspace.ts`            |
| Pool types         | `frontend/src/types/pool.ts`                  |
