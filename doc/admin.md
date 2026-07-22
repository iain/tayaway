# Admin site

The operator-only maintenance site: job overviews, audit log, user counts,
and client protocol-version stats, at `https://admin.tayaway.nl`. One user
(the operator), read-only dashboards; break-glass actions are a planned
follow-up.

## Architecture

- **Separate process, separate vhost.** `backend/admin/` is a second Roda
  app (`AdminApp`) booted by `admin/falcon.rb` on :9393, running as its own
  quadlet container (`ops/quadlet/admin.container`, same backend image,
  different command). It is never routed from the main app, so a main-app
  auth or routing bug can't expose an admin endpoint — and vice versa.
- **Server-rendered.** ERB via Roda's render plugin (escape-by-default),
  two static CSS files, one small vanilla JS file for the passkey ceremony
  and logout. No SPA, no build step, no service worker.
- **Styled by Pico.** `public/pico.classless.min.css` is the vendored
  class-less build of [Pico](https://picocss.com) (v2.1.1 — the version is
  in the file's banner comment; upgrade by re-downloading it, there is no
  package manager here on purpose). It styles bare semantic elements, so
  the templates are plain HTML — `<article>` is a card, `<nav><ul><li>` is
  the topbar and the filter rows — and it brings dark mode, form controls
  and focus rings along for free. `public/admin.css` is deliberately tiny
  on top: only the dashboard stat tiles and a few status-color utilities,
  written against Pico's own `--pico-*` custom properties so they follow
  light/dark with everything else. Reach for a `--pico-*` override before
  writing a new rule, and keep it that way — it is what makes the admin
  site cheap to maintain. It shares nothing with the main frontend's
  Tailwind/DESIGN.json system, which would drag a build step in with it.
- **Pages.** `/` is the dashboard and holds counters only — jobs by
  state, users, client versions — with the listings on their own pages
  behind the topbar nav. `/jobs?state=due|scheduled|retrying|dead` lists
  the rows behind each job counter; the states overlap exactly as the
  counters do, so a retrying job also shows up under due or scheduled
  depending on where its backoff landed. `/jobs/:id` is the full row for
  one job: payload, attempts against the retry budget, and the
  untruncated last error. `/audit?outcome=` is the audit log.
- **Read models only.** `Admin::Stats` queries `async_jobs`,
  `audit_log_entries`, `users`, and `sessions` (including
  `last_seen_client_version` — see doc/protocol-versioning.md) and returns
  plain hashes to the templates.
- **Own auth store.** Passkey credentials and admin sessions live in a
  SQLite file (`Admin::State`, migrations in `db/admin_migrations/`,
  applied at boot), not in Postgres — see "Security layers" for why. The
  main DB connection is only ever read from.

## Security layers

| Layer | Stops |
| --- | --- |
| mTLS at the edge | Everyone without the operator client cert — the TLS handshake fails before HTTP, so scanners see nothing |
| Separate process/vhost | Main-app vulnerabilities leaking into admin surfaces |
| Admin-local passkey login | A stolen or borrowed device that has the client cert installed |
| `admin_sessions` (12 h TTL, digested tokens, `__Host-` cookie, SameSite=Strict) | Session theft/fixation, cross-site request forgery (plus the `X-CSRF-Protection` header on every mutation) |
| Read-only DB role (`ADMIN_DATABASE_URL`) | Injection or logic bugs in dashboard queries — the role physically cannot write |

Admin auth is fully self-contained: passkeys and sessions live in the
admin's own SQLite store (`Admin::State`, `ADMIN_STATE_PATH`), never in
the main database. The RP ID is the admin host itself (`ADMIN_ORIGIN`),
not the apex — admin passkeys are separate credentials from main-app
passkeys, enrolled on the admin site. Two things follow:

- **Operator login survives main-DB incidents.** Restoring a backup,
  debugging auth corruption, or a wiped database cannot lock you out of
  the dashboard — which is exactly when you need it.
- **Main-app compromise cannot mint admin access.** A bug that lets an
  attacker register a main-app passkey gains nothing here.

Enrollment is the authorization gate (there is no email allowlist):
registration is open only while the credential store is empty — i.e.
first boot, still behind mTLS — and afterwards only from a signed-in
admin session (dashboard → "Add passkey"). The empty-store check re-runs
inside the insert transaction, so two racing first-boot tabs cannot both
enroll. Losing every enrolled device = delete the SQLite file on the
admin volume and enroll again; the store holds only auth material, so
there is nothing to back up.

## Configuration

| Var | Where | Purpose |
| --- | --- | --- |
| `ADMIN_ORIGIN` | quadlet | Origin the operator's browser uses (`https://admin.tayaway.nl`) — WebAuthn RP ID is its host |
| `ADMIN_STATE_PATH` | quadlet | SQLite file for admin credentials/sessions, on the `tayaway-admin` volume |
| `ADMIN_DATABASE_URL` | `.env.production.yaml` (sops) | Read-only role for dashboard queries; falls back to `DATABASE_URL` when unset |
| `ADMIN_FALCON_URL` | quadlet | Bind URL; `http://0.0.0.0:9393` in the container |

## Operator CA and client cert

The edge requires a client certificate signed by a tiny personal CA
(`require_and_verify` in `ops/host/admin.caddy`). The minted CA lives in
the repo: `ops/admin-ca/ca.pem` (public, plain) and
`ops/admin-ca/secrets.yaml` (sops, operator-recipient only — holds
`ca_key`, `client_key`, `client_pem`; see `.sops.yaml`). Plaintext key
files in that directory are gitignored. To mint from scratch:

```sh
# CA (10 years). ca.key goes into secrets.yaml (sops) — it can mint admin access.
openssl ecparam -genkey -name prime256v1 -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 3650 \
  -subj "/CN=Tayaway admin CA" -out ca.pem

# Client cert (1 year), then a PKCS#12 bundle for browser/phone import.
openssl ecparam -genkey -name prime256v1 -out client.key
openssl req -new -key client.key -subj "/CN=iain" -out client.csr
openssl x509 -req -in client.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -sha256 -days 365 -out client.pem
openssl pkcs12 -export -inkey client.key -in client.pem -name "tayaway-admin" \
  -out tayaway-admin.p12
```

Import `tayaway-admin.p12` into the OS keychain (macOS: Keychain Access;
iOS: AirDrop → Settings → Profile; Android: Settings → Security →
Install a certificate). Only `ca.pem` (the public half) goes to the server.

Renewal = mint a new client cert from the same CA; nothing server-side
changes. Losing a device = mint a new CA, replace `ca.pem`, re-provision —
the old cert stops working at the next edge restart.

## Read-only DB role

On the box (`sudo podman exec -it db psql -U tayaway tayaway`):

```sql
CREATE ROLE tayaway_admin_ro LOGIN PASSWORD '<generate>';
GRANT CONNECT ON DATABASE tayaway TO tayaway_admin_ro;
GRANT USAGE ON SCHEMA public TO tayaway_admin_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO tayaway_admin_ro;
-- Future tables created by migrations (which run as tayaway) inherit SELECT:
ALTER DEFAULT PRIVILEGES FOR ROLE tayaway IN SCHEMA public
  GRANT SELECT ON TABLES TO tayaway_admin_ro;
```

Then add `ADMIN_DATABASE_URL=postgres://tayaway_admin_ro:<pw>@db:5432/tayaway`
to `.env.production.yaml` (sops). Note the fallback: while unset, dashboards
run on the main (writable) role — functional, just without this layer.

Auth flows never touch the main database: credentials, sessions, and
sign-count bumps all live in the admin's own SQLite store.

## Rollout checklist (first deploy)

1. `tofu apply` in `ops/` — creates the `admin` A/AAAA records.
2. Mint the CA + client cert (above); import the `.p12` on your devices.
3. Copy the CA to the box:
   `scp ca.pem tayaway@tayaway.nl:/tmp/ && ssh … 'sudo install -m 0644 -o root -g root /tmp/ca.pem /etc/tayaway/caddy-admin/ca.pem && rm /tmp/ca.pem'`
   (create the dir first if provision hasn't run yet).
4. Create the read-only role + add `ADMIN_DATABASE_URL` to the sops env.
5. Re-run provision (`mise run vm:provision …`) — syncs the admin quadlet
   and its state volume, installs `admin.caddy` (now that ca.pem exists),
   and updates self-deploy.
6. Deploy (`mise run deploy …`) — starts the admin container (the SQLite
   store migrates itself at boot), restarts the edge.
7. First visit: `https://admin.tayaway.nl` without the client cert must
   fail the TLS handshake; with it, you land on `/enroll` — enroll this
   device's passkey (the store is empty, so enrollment is open behind the
   mTLS gate), then sign in with it. Add further devices from the
   dashboard's "Add passkey" while signed in.

Until every step is done the site fails closed: no DNS → unreachable, no
ca.pem → no vhost, and enrollment shuts the moment the first credential
exists.

## Development

```sh
mise run admin:dev        # admin site on http://localhost:9393
```

No configuration needed: `ADMIN_ORIGIN` defaults to
`http://localhost:9393` (localhost is a WebAuthn secure-context
exception, so plain http works) and the store defaults to
`tmp/admin_state.development.db`. First visit redirects to `/enroll` —
enroll a passkey right there; it is independent of any main-app passkey.
No mTLS locally — that layer exists only at the production edge. To
start over, delete the `tmp/admin_state.development.db*` files.

Specs live in `spec/admin/` (request specs against `AdminApp`) and
`spec/services/admin/`.
