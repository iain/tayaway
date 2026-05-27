# Co-hosting other projects on this VPS

The box has spare capacity for small, unrelated side projects. This is how to
run them beside tayaway **without coupling** — no monorepo, no extracting
`ops/`. Each project keeps its own repo, image, and secrets; the box just hosts
them side by side.

## Model: rootful edge, rootless tenants

The VPS is a tiny single-node platform; each project is an isolated **tenant**.
Only two things are shared: **ports 80/443** (so there's one Caddy, the existing
`edge`, routing by hostname with a cert per domain) and **the host kernel**
(co-tenancy, not VM isolation — fine for your own code, not untrusted code).

- **The `edge` stays rootful.** It binds 80/443 and terminates TLS, so it sees
  real client IPs — which keeps tayaway's geoip and logging honest. (A *rootless*
  edge would masquerade them; see below.)
- **Each tenant runs rootless, under its own unprivileged user.** An escape is
  confined to that user's subuid range — it can't touch tayaway's files or DB.
- **Edge reaches a tenant via the host, not a shared network.** The tenant
  publishes to `127.0.0.1:<port>`; the edge reverse-proxies to it. Tenant
  networks never touch `systemd-tayaway`, so no tenant can reach `db:5432`.

tayaway itself stays rootful for now (already hardened: `cap-drop=all`,
`ReadOnly=true`, AppArmor). Converting it is a future-rebuild task, not in-place
surgery — see [below](#converting-tayaway-itself-later).

## Prerequisites: make tayaway a good neighbour

Two one-time changes in this repo. Neither is done yet.

1. **Caddy loads tenant config from a host dir.** The Caddyfile is baked into the
   edge image (`containers/Containerfile:114`), so today a new domain means
   rebuilding tayaway. Add `import /etc/caddy/sites/*.caddy` to
   `containers/Caddyfile`, mount `/etc/caddy/sites:ro` into the edge, and have
   `provision.sh` create the dir. Then domains are just files dropped there.
   **Caveat:** a broken snippet fails Caddy's whole load — every tenant deploy
   must `caddy validate` before `caddy reload`.
2. **Scope the provisioner.** `provision.sh` rsyncs `ops/quadlet/` to
   `/etc/containers/systemd/` with `--delete-after`, so it wipes foreign units.
   Limit the delete to tayaway's own units (rsync `--filter='protect …'`, a
   manifest, or a `tayaway-*` naming convention). *Rootless* tenant units live
   in the user's `~/.config/containers/systemd/`, already out of range — this
   only matters if you ever run a rootful tenant.

## Tenant anatomy

Each side project, in its own repo:

| Piece | What |
| --- | --- |
| Image | Own `Containerfile`, pushed to a registry (private GHCR is fine). |
| Quadlet | `<slug>-web.container` (+ db etc.) under the tenant user's `~/.config/containers/systemd/`; publishes web to `127.0.0.1:<port>`. |
| Network | Own `<slug>.network`. **Never** `systemd-tayaway`. |
| Caddy | `<slug>.caddy` in `/etc/caddy/sites/` → `reverse_proxy <host-gateway>:<port>`. |
| Secrets | Own age key / env. Never reuse tayaway's. |
| DNS | Own IaC or click-ops; not in tayaway's tofu state. |
| Deploy | Pull image → sync quadlet + caddy snippet → `systemctl --user daemon-reload` + restart → `caddy validate` + reload edge → curl. |

Set `MemoryMax=` / `--cpus=` on tenant units so a runaway can't starve tayaway.

### Per-user rootless setup (once per tenant)

```bash
sudo useradd --create-home --shell /usr/sbin/nologin acme
sudo loginctl enable-linger acme    # user units start at boot, no session
grep -q '^acme:' /etc/subuid || echo 'acme:300000:65536' | sudo tee -a /etc/subuid /etc/subgid
# deploy as that user; quadlets in ~acme/.config/containers/systemd/
```

## Rootless investigation

Box facts (`new.tayaway.nl`, 2026-05-27): `podman 4.9.3`, **no `pasta`** (and 4.9
predates pasta-as-default — that's 5.0+), so rootless networking falls back to
**slirp4netns**, which **masquerades the client IP**; `ip_unprivileged_port_start
= 1024`.

Implications: client-IP/geoip and privileged-port limits are *rootless-edge*
problems, both avoided by keeping the edge rootful. Per-tenant rootless works
today on slirp4netns (fine for outbound + one loopback port; slower under heavy
network load — install `passt` + set `default_rootless_network_cmd = pasta` if a
tenant is network-hot).

### Converting tayaway itself (later)

Deferred to a rebuild, because it disturbs what we just stabilised:
the populated `tayaway-db` volume needs re-chowning into the user's subuid range
(free during a dump/restore, risky live); networking moves off netavark host-DNAT
(re-opening the IPv6 work); and all systemd plumbing moves to `--user` + linger.
Gather first: a newer podman (5.x) with `passt`, and confirmation the edge still
logs real client IPs on whatever backend you land on.

---

## Template: bring a side project to production

Copy into a GitHub issue **or** paste to an AI agent. Fill the `INPUTS`; the rest
is the standing contract for this box.

````markdown
# Onboard side project `<slug>` to the tayaway VPS

Bring my side project live as an isolated tenant on the shared OVH VPS that runs
tayaway. Follow `ops/co-hosting.md`: **rootful shared edge, this tenant rootless
under its own user**, isolated from tayaway's network/secrets/data.

## INPUTS
- Slug (dns-safe): ____      - Repo / branch: ____
- Image (registry path+tag, or "build from repo"): ____
- Domain(s): ____            - Container port: ____
- Stateful? (none / SQLite / own Postgres): ____
- Persistent paths: ____     - Secret/env names: ____
- Resource caps: ____ (default 256M / 0.5 cpu)
- Health path: ____ (default `/`)   - Backups? ____ (default none)

## Constraints (do not violate)
- Runs rootless under a dedicated user `<slug>` (useradd + enable-linger +
  subuid); quadlets in its `~/.config/containers/systemd/`, `systemctl --user`.
- Joins only its own `<slug>.network`; never `systemd-tayaway`; never reads
  tayaway's age key or `.env.production*`.
- Publishes to `127.0.0.1:<port>`; the rootful edge proxies to it. Don't bind
  80/443.
- Add the domain via `/etc/caddy/sites/<slug>.caddy`; `caddy validate` before
  reload (a broken snippet takes tayaway down).
- Cap memory/cpu. DNS outside tayaway's tofu. Name units `<slug>-*`.

## Deliverables
1. Rootless user + linger + subuid.
2. Quadlet unit(s), resource-capped, publishing to loopback.
3. `<slug>.caddy` snippet (+ security headers if apt).
4. Registry auth if private.
5. A `deploy.sh`: pull → sync quadlet + snippet → daemon-reload + restart →
   caddy validate + reload → curl health.
6. DNS A + AAAA for the domain.
7. Verify: `curl https://<domain><health>` OK with a valid cert over IPv4 **and**
   IPv6; tenant healthy; tayaway `/health` still 200.

## Hands off
tayaway's quadlets/network/volumes/secrets/`provision.sh`; ports 80/443; any
restart of `db`/`web`/`edge` beyond a Caddy reload.
````
