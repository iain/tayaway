# ops/

Declarative recipe for tayaway's production infrastructure. Three layers,
each tracked in git:

| Layer                | What it owns                                                                                       | Where                                |
| -------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------ |
| Cloud-level state    | OVH DNS, WAL-G bucket, scoped S3 user, state bucket                                                | `*.tf`, `bootstrap/*.tf`             |
| OS-side setup        | apt packages, tayaway user, journald caps, nftables baseline, kernel reboot, quadlet sync          | `provision.sh`                       |
| Compute (manual)     | The VPS itself — ordered through the OVH manager once per rebuild                                  | `README.md` "Ordering the VPS" below |

The VPS is the only piece *not* in terraform. OVH's `ovh_vps` resource
exists but doesn't expose a `user_data` field, and VPSes are billed
monthly — an accidental `tofu destroy` would cost a month of the plan.
For a hobby-scale service we rebuild approximately never, the saner
trade is: order the VPS by hand, then run `mise run vm:provision` to
bring it up. `provision.sh` is idempotent and is the only OS-side code
path; re-run it whenever the OS config or quadlet units change.

## What this Phase 3 PR ships

A complete recipe — three or four commands of human work brings up a
fresh VPS next to the existing production VPS without touching it.
Phase 4 fills in `quadlet/` with the actual unit files; Phase 7 (cutover)
flips DNS.

The deliberate gap: the existing apex `tayaway.nl` A record is **not** in
this config. `ovh_domain_zone_record` is per-record, so leaving it out
means `tofu apply` cannot redirect production while the new stack is
being commissioned. Cutover imports it explicitly.

## First-time bring-up

You need: an age private key matching one of the recipients in
`../.sops.yaml` (yours, on a laptop that's been onboarded), and an ssh
public key.

Operator credentials — the OVH API triple and the state-bucket S3
keypair — live sops-encrypted in `ops/secrets.yaml` and are decrypted
into tofu's process env by mise on every `tofu` invocation from `ops/`
or below. mise picks the age key up from `$SOPS_AGE_KEY_FILE`; export
it once in your shell config:

```fish
set -gx SOPS_AGE_KEY_FILE ~/.config/sops/age/keys.txt
```

(`~/.config/sops/age/keys.txt` is sops's standard location. mise's own
default is `~/.config/mise/age.txt` — pick whichever; the env var
just makes it explicit.)

### 0. Populate `backend/.env.production.yaml` (one-time)

The committed file ships with `PLACEHOLDER_REPLACE_BEFORE_DEPLOY`
values for `POSTGRES_PASSWORD`, `DATABASE_URL`, `APP_SECRET`, and
`VAPID_PRIVATE_KEY`. Open it via sops and fill in real values:

```fish
mise x sops -- sops ../backend/.env.production.yaml
```

`migrate.container` runs `rake config:validate` before any migration,
so a deploy attempted with unfilled placeholders fails at the
validation step (invalid base64, missing required value) before `web`
ever sees traffic — but better to catch it here than at deploy time.

Pair this with the non-secret half (`backend/.env.production`):
`VAPID_PUBLIC_KEY` must be set there alongside the private key, or the
push feature stays disabled.

### 1. Bootstrap the state bucket

Local `terraform.tfstate` is gitignored — back it up to wherever your
laptop secrets live. Only re-run this if the bucket itself is gone.

```fish
cd ops/bootstrap
mise x opentofu -- tofu init
mise x opentofu -- tofu apply
```

Capture the credentials it printed so the main config's S3 backend can
authenticate. The line in `providers.tf` hard-codes the bucket name —
if you overrode `bucket_name` or `region_name` in this step, update
`bucket` / `region` / `endpoints.s3` in `providers.tf` to match.

```fish
set -gx AWS_ACCESS_KEY_ID (mise x opentofu -- tofu output -raw state_access_key_id)
set -gx AWS_SECRET_ACCESS_KEY (mise x opentofu -- tofu output -raw state_secret_access_key)
```

Once the bucket exists, the keypair these printed is the one that
should live in `ops/secrets.yaml`. Edit and re-encrypt with:

```fish
mise x sops -- sops ops/secrets.yaml          # opens $EDITOR on the cleartext, re-encrypts on save
```

(If `ops/secrets.yaml` is missing entirely — true total-loss with no
git — the chicken-and-egg path is: pass the OVH triple via `OVH_*`
env vars for this single `tofu apply`, then create `secrets.yaml`
from scratch and `sops encrypt -i` it.)

### 2. Order the VPS

In the OVH manager: **Bare Metal Cloud → VPS → Order**, then:

| Option       | Value                                                                                  |
| ------------ | -------------------------------------------------------------------------------------- |
| Model        | **VPS-1** (4 vCore / 8 GB RAM / 75 GB SSD, ~€6.68/month inc VAT)                       |
| Datacenter   | Match the current prod VPS for low-latency DB migration during cutover                 |
| OS           | **Ubuntu 24.04 LTS** (anything systemd + podman 4+ works; LTS keeps the surface small) |
| Commit       | 1 month (rolling — gives you a low-cost exit if anything is wrong)                     |
| SSH key      | **Attach your existing key.** Without one, OVH emails a root password and you have to scp the key in by hand on first login |
| Backups, DDoS, snapshot extras | Decline — none of them earn their price for this workload (WAL-G covers PITR off-host) |

Wait for the order to provision (5–10 minutes); OVH emails the
hostname and IP when ready. Both also show under **My services → VPS**
in the manager.

### 3. Add the DNS record + S3 bucket

`TF_VAR_vps_ipv4` (committed in `ops/mise.toml`) needs to point at the
address from the previous step before the apply — update it and commit
the change, or override on the command line for a one-off. This creates
`new.tayaway.nl` and the WAL-G bucket + S3 user.

```fish
cd ..
mise x opentofu -- tofu init
mise x opentofu -- tofu apply
```

### 4. First provision — OS bootstrap

Connect as whatever user the VPS image exposes — `ubuntu` on the
Ubuntu cloud image (most common), `debian` on Debian, `root` on the
generic VPS image — on the default port **22**. `provision.sh` creates
the `tayaway` user from that user's `authorized_keys`, installs
packages (including `fail2ban`), writes journald + nftables + apt
configs, and reboots once if a kernel update came in. It does **not**
touch sshd this run — port 22 stays open and the connecting user keeps
working so the reboot reconnect lands cleanly.

```fish
mise run vm:provision ubuntu@<vps-ip>
```

After it exits, both `ssh ubuntu@<ip>` and `ssh tayaway@<ip>` on port
22 work.

### 5. Hand-drop the age private key

Only manual secret-handling step in the whole recipe. The VPS gets the
**production** age key — distinct from the operator's laptop key. Both
are listed as recipients on `backend/.env.production.yaml` in
`../.sops.yaml`; the VPS uses its own key at runtime so that compromise
of any single laptop doesn't widen the production key's surface.

Store the production private key in your password manager between
generations. Total-loss recovery either restores it from there to the
new VPS, or generates a fresh key, updates `../.sops.yaml`, runs `sops
updatekeys backend/.env.production.yaml`, and commits.

```fish
# fetch the production key from your password manager into a temp file first
scp /tmp/prod-age.key tayaway@<vps-ip>:/tmp/age.key
ssh tayaway@<vps-ip> 'sudo install -m 0400 -o root -g root /tmp/age.key /etc/tayaway/age.key && rm /tmp/age.key'
rm /tmp/prod-age.key
```

### 6. Second provision — quadlets + ssh hardening

This run does the deploy-side work (age key check, quadlet sync,
daemon-reload, image pre-pull) and then hardens sshd as its **last**
step: writes `/etc/ssh/sshd_config.d/00-tayaway-hardening.conf` (port
50022, `AllowUsers tayaway ubuntu` — ubuntu kept as emergency fallback,
password auth off, kbd-interactive off, `PermitRootLogin no`), locks
the root account, rewrites nftables to 22 → 50022, restarts
`ssh.service` (or `ssh.socket` when socket activation is in play), and
**verifies sshd actually bound 50022 before touching the sentinel**.
The dropin sorts alphabetically before cloud-init's
`50-cloud-init.conf`, so its directives beat cloud-init's defaults
(notably OVH's image sets `PasswordAuthentication yes` there).
`KillMode=process` in `ssh.service` keeps your live session alive
across the restart; only the master sshd is killed, per-connection
children survive.

> **Keep an ssh session open in a separate terminal** through this
> step. The hardening is well-tested but the failure mode if something
> goes wrong (sshd doesn't bind 50022, nftables already blocks 22) is
> hard total-lockout. Your live session is the cheapest recovery path
> — OVH's rescue mode is the fallback.

```fish
mise run vm:provision tayaway@<vps-ip>
```

The script prints a banner at the end with the `~/.ssh/config` block
to add. Do it now so future runs find the new port without flags.

### 7. Wire the new host into `~/.ssh/config`

Append the block the script printed:

```
Host new.tayaway.nl
  Port 50022
  User tayaway
  IdentityFile ~/.ssh/id_ed25519
```

`ssh new.tayaway.nl` should now connect on 50022 as tayaway. If you
need to reach it by IP during commissioning, add a second
`Host <vps-ip>` block with the same body.

### 8. Bring up the quadlet stack

Future `mise run vm:provision tayaway@new.tayaway.nl` runs are
idempotent — both sentinels are set, all per-run steps converge. From
Phase 4 on, this is also what delivers the stack: it syncs
`quadlet/*` to `/etc/containers/systemd/`, delivers the env files to
`/etc/tayaway/env/`, installs `sops`, the `tayaway-db-secret` host
oneshot, and the monthly `geoip.timer`, daemon-reloads, and pre-pulls
the images in `images.txt`.

Two one-time prerequisites the provision can't do for you:

- **GHCR login** — `backend`/`edge` are private packages. Log the VPS
  in once with a `read:packages` PAT (rootful podman, so as root):

  ```fish
  ssh new.tayaway.nl 'sudo podman login ghcr.io -u <github-user>'
  ```

- **Bump the image SHAs** in `images.txt` and `quadlet/*.container` to
  this stack's built SHA. The committed value must be a commit for
  which CI published all three images (`backend`, `edge`, `geoip`).

Then provision and start the stack. The units have an [Install] section
so they auto-start on boot; the first time, start them by hand. Starting
`edge` pulls in `web → migrate → db → tayaway-db-secret` via
dependencies; `geoip` is one-shot and seeds the volume:

```fish
mise run vm:provision tayaway@new.tayaway.nl
ssh new.tayaway.nl 'sudo systemctl start geoip.service edge.service'
ssh new.tayaway.nl 'systemctl status web edge db --no-pager'
```

Caddy provisions a real Let's Encrypt cert for `new.tayaway.nl` on
first start (`SITE_ADDRESS` in `edge.container`). Watch it land with
`journalctl -u edge -f`. Cutover to the apex is a separate Phase 7 PR.

## Total-loss recovery

The whole VPS is gone or unrecoverable.

1. **State bucket also gone:** `cd ops/bootstrap && tofu apply` — rare.
2. Order a new VPS-1 in the OVH manager (step 2 above).
3. `tofu apply -var "vps_ipv4=<new-ip>" …` to repoint `new.tayaway.nl`
   and recreate the WAL-G credentials.
4. `mise run vm:provision` as the image's default user on port 22
   (step 4).
5. scp the age key (step 5).
6. `mise run vm:provision tayaway@<ip>` — does quadlets + ssh
   hardening (step 6).
7. Update `~/.ssh/config` with the printed Port 50022 block (step 7).
8. `sudo podman login ghcr.io`, then `systemctl start geoip edge`
   (step 8).
9. WAL-G restore (see `doc/operations/walg.md` — landing in Phase 5).

~20 min, four or five commands of human work plus the OVH-manager
order.

## Drift detection

`.github/workflows/ops-drift.yml` runs `tofu plan` on every PR that
touches `ops/**` and on a weekly schedule. A non-empty plan fails the
job. Catches "someone clicked something in the OVH console" before it
becomes invisible state.

The job decrypts `ops/secrets.yaml` with the CI age private key —
exactly the same path the laptop uses, just with a different age
recipient. Setup is a single GitHub secret:

```fish
mise x age -- age-keygen -o /tmp/ci-age.key
mise x age -- age-keygen -y /tmp/ci-age.key   # public recipient — add to ../.sops.yaml and sops updatekeys
gh secret set SOPS_AGE_KEY < /tmp/ci-age.key
rm /tmp/ci-age.key
```

The CI recipient is added to `ops/secrets.yaml` only — not to
`backend/.env.production.yaml`. A compromised CI run can therefore
leak operator credentials (recoverable: rotate the OVH triple), but
not the database password or any other runtime secret. That's the
structural reason production runtime secrets never reach a GitHub
runner.

The OVH triple in `secrets.yaml` is full read-write. The original
design called for a separate read-only token, but OVH's API rejects
`GET` on `/cloud/project/{id}/user/{uid}/s3Credentials/{key}` for any
read-only-scope token regardless of how broad `GET /*` is —
undocumented "endpoints that ever return secrets require non-readonly"
behavior. The drift workflow needs to refresh that resource, so it
needs the full token. The risk is bounded by the workflow itself: only
`tofu plan -detailed-exitcode` ever runs; there is no `apply`
codepath, so the write capability is present but never exercised.

## Why not annual provisioning drills

The migration plan in #440 originally called for an annual full
provisioning drill (spin up a fresh sandbox VM, throw it away). That
was sized against Public Cloud's hourly billing; on VPS the same drill
costs a full month of the plan and the OVH-manager order can't be
automated either. The drift-detection job is what catches `*.tf` drift;
`provision.sh` is exercised every time you change anything ops-side,
so it gets meaningful coverage without a dedicated drill.

## Why not Ansible / Chef / etc.

The whole point is "rebuild from a short recipe, not a memorised
dance." Two files (`provision.sh`, `*.tf`) plus the quadlet units fits
in one head and reads in one sitting; pulling in a configuration-
management framework would obscure that for a one-VPS deployment
whose configuration is already trivially declarative.
