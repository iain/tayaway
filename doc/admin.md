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
  one static CSS file, one small vanilla JS file for the passkey ceremony
  and logout. No SPA, no build step, no service worker.
- **Read models only.** `Admin::Stats` queries `async_jobs`,
  `audit_log_entries`, `users`, and `sessions` (including
  `last_seen_client_version` — see doc/protocol-versioning.md) and returns
  plain hashes to the templates.

## Security layers

| Layer | Stops |
| --- | --- |
| mTLS at the edge | Everyone without the operator client cert — the TLS handshake fails before HTTP, so scanners see nothing |
| Separate process/vhost | Main-app vulnerabilities leaking into admin surfaces |
| Passkey login + `ADMIN_EMAILS` allowlist | A stolen or borrowed device that has the client cert installed |
| `admin_sessions` (12 h TTL, digested tokens, `__Host-` cookie, SameSite=Strict) | Session theft/fixation, cross-site request forgery (plus the `X-CSRF-Protection` header on every mutation) |
| Read-only DB role (`ADMIN_DATABASE_URL`) | Injection or logic bugs in dashboard queries — the role physically cannot write |

Login reuses the main app's WebAuthn credentials: the RP ID is the apex
(`tayaway.nl`), which the registrable-suffix rule makes valid on
`admin.tayaway.nl`, so the existing passkey works — no separate
registration. `WEBAUTHN_EXTRA_ORIGINS` must include the admin origin.
`ADMIN_EMAILS` is authorization, not authentication: an email on the list
still needs that user's passkey and the client cert.

## Configuration

| Var | Where | Purpose |
| --- | --- | --- |
| `ADMIN_EMAILS` | `.env.production` (non-secret) | CSV allowlist; empty disables admin login entirely |
| `WEBAUTHN_EXTRA_ORIGINS` | `.env.production` | Must include `https://admin.tayaway.nl` |
| `ADMIN_DATABASE_URL` | `.env.production.yaml` (sops) | Read-only role for dashboard queries; falls back to `DATABASE_URL` when unset |
| `ADMIN_FALCON_URL` | quadlet | Bind URL; `http://0.0.0.0:9393` in the container |

## Operator CA and client cert

The edge requires a client certificate signed by a tiny personal CA
(`require_and_verify` in `ops/host/admin.caddy`). Mint it once, locally:

```sh
# CA (10 years). Keep ca.key offline/sops-encrypted — it can mint admin access.
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

On the box (`sudo podman exec -it db psql -U tayaway tayaway_production`):

```sql
CREATE ROLE tayaway_admin_ro LOGIN PASSWORD '<generate>';
GRANT CONNECT ON DATABASE tayaway_production TO tayaway_admin_ro;
GRANT USAGE ON SCHEMA public TO tayaway_admin_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO tayaway_admin_ro;
-- Future tables created by migrations (which run as tayaway) inherit SELECT:
ALTER DEFAULT PRIVILEGES FOR ROLE tayaway IN SCHEMA public
  GRANT SELECT ON TABLES TO tayaway_admin_ro;
```

Then add `ADMIN_DATABASE_URL=postgres://tayaway_admin_ro:<pw>@db:5432/tayaway_production`
to `.env.production.yaml` (sops). Note the fallback: while unset, dashboards
run on the main (writable) role — functional, just without this layer.

Auth flows (login/logout) intentionally use the main `DB` connection — they
must write `admin_sessions` and bump passkey sign counts.

## Rollout checklist (first deploy)

1. `tofu apply` in `ops/` — creates the `admin` A/AAAA records.
2. Mint the CA + client cert (above); import the `.p12` on your devices.
3. Copy the CA to the box:
   `scp ca.pem tayaway@tayaway.nl:/tmp/ && ssh … 'sudo install -m 0644 -o root -g root /tmp/ca.pem /etc/tayaway/caddy-admin/ca.pem && rm /tmp/ca.pem'`
   (create the dir first if provision hasn't run yet).
4. Create the read-only role + add `ADMIN_DATABASE_URL` to the sops env.
5. Verify `ADMIN_EMAILS` in `backend/.env.production` matches your account
   email, then re-run provision (`mise run vm:provision …`) — syncs the
   admin quadlet, installs `admin.caddy` (now that ca.pem exists), and
   updates self-deploy.
6. Deploy (`mise run deploy …`) — migrates `admin_sessions`, starts the
   admin container, restarts the edge.
7. Check: `https://admin.tayaway.nl` without the cert must fail the TLS
   handshake; with it, the login page appears and your passkey signs in.

Until every step is done the site fails closed: no DNS → unreachable, no
ca.pem → no vhost, no `ADMIN_EMAILS` → login always 403, no migration →
500s behind the mTLS gate.

## Development

```sh
mise run admin:dev        # admin site on http://localhost:9393
```

`.env.development` is gitignored, so add the admin keys to your local copy:

```sh
ADMIN_EMAILS=test@example.com                # the seeded user
WEBAUTHN_EXTRA_ORIGINS=http://localhost:9393 # passkey ceremony on the admin port
```

Register a passkey for the test user in the SPA first (dev-login → profile
→ passkeys), then sign in at :9393 with it. No mTLS locally — that layer
exists only at the production edge.

Specs live in `spec/admin/` (request specs against `AdminApp`) and
`spec/services/admin/`.
