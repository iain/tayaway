# Client↔server protocol versioning

The frontend is a PWA: after a deploy, clients keep running their cached
bundle — sometimes for days (a phone that only reopens the app next week).
Backwards-incompatible API changes therefore can't just ship; old clients
must be moved off the old behavior deliberately. This document describes the
version gate that makes that safe.

## The two numbers

| Constant | Lives in | Moves when |
| --- | --- | --- |
| `PROTOCOL_VERSION` | `frontend/src/api/protocolVersion.ts` | a change ships that older clients can't survive |
| `ClientProtocol::MIN_SUPPORTED_VERSION` | `backend/app/client_protocol.rb` | the old behavior is actually removed |

The gap between them is the compatibility window. Both files carry a bump
log — keep it current, it's what tells you which bumps were real breaks.

Neither of these is poolDb's `CACHE_VERSION`, which versions a client's own
IndexedDB cache against its own code and moves far more often (see the
comparison note in `protocolVersion.ts`).

## How the gate works

- Every API request carries `X-Client-Version` (added centrally in
  `client.ts`); every WebSocket connect carries `v=` on the URL.
- The backend checks the header for all `/api` paths before routing
  (`verify_client_version!` in `app.rb`) and answers **426 Upgrade
  Required** with `{ error, minSupportedVersion }` when the client is below
  the minimum. The WS route answers an `update_required` message and closes
  (`routes/ws.rb`) — that path only fires in the narrow race where a ticket
  minted before a deploy is redeemed after it, since the ticket fetch itself
  is an API request.
- Clients that predate versioning send no header and count as version 0.
- The frontend intercepts both signals into `handleUpdateRequired()`
  (`api/updateRequired.ts`): blocking overlay, WebSocket disconnected (no
  reconnect loop against the gate), and the pending service worker update is
  force-applied immediately instead of waiting for a quiet moment
  (`forceUpdateNow` in `api/autoUpdate.ts`). The reload lands on the new
  version.
- The offline command queue treats a 426 like a pause, not a failure:
  nothing is rolled back or dropped; rows replay after the reload. Each row
  is stamped with the `protocolVersion` that wrote it, so a future build can
  migrate or drop old-format rows.

## Shipping a breaking change

1. **Deploy N** — ship the new behavior *alongside* the old (the same
   additive discipline as `doc/database-migrations.md`), and bump
   `PROTOCOL_VERSION` in the same deploy.
2. **Wait** — until the fleet has updated past N. Server logs tag rejected
   requests with `[Protocol]`; client versions arrive on every request if
   you need to check adoption.
3. **Deploy M** — remove the old behavior and raise
   `MIN_SUPPORTED_VERSION` to N in the same deploy. Stragglers get the
   update-required flow instead of broken requests.

Never raise `MIN_SUPPORTED_VERSION` above the `PROTOCOL_VERSION` that is
live at the same time — that would gate every client, including current
ones.

## Caveat: queued offline mutations

The gate protects the request/sync surface, but a breaking change to a
**mutation endpoint** has one more consumer: old-format rows in the offline
command queue, replayed *by the new build* after the forced update. Either
keep the server accepting the old mutation shape for the window, or add a
client-side migration keyed off the row's `protocolVersion` stamp
(`StoredCommand` in `api/commandDb.ts`).
