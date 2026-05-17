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

You need: OVH API credentials (set in `ops/mise.local.toml` so they
don't enter your shell history), an age keypair, and an ssh public key.

### 1. Bootstrap the state bucket

Local `terraform.tfstate` is gitignored — back it up to wherever your
laptop secrets live. Only re-run this if the bucket itself is gone.

```fish
cd ops/bootstrap
mise x opentofu -- tofu init
mise x opentofu -- tofu apply -var "service_name=<project-id>"
```

Capture the credentials it printed so the main config's S3 backend can
authenticate. The line in `providers.tf` hard-codes the bucket name —
if you overrode `bucket_name` or `region_name` in this step, update
`bucket` / `region` / `endpoints.s3` in `providers.tf` to match.

```fish
set -gx AWS_ACCESS_KEY_ID (mise x opentofu -- tofu output -raw state_access_key_id)
set -gx AWS_SECRET_ACCESS_KEY (mise x opentofu -- tofu output -raw state_secret_access_key)
```

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

`vps_ipv4` is the address from the previous step. This creates
`new.tayaway.nl` and the WAL-G bucket + S3 user.

```fish
cd ..
mise x opentofu -- tofu init
mise x opentofu -- tofu apply \
  -var "service_name=<project-id>" \
  -var "vps_ipv4=<from step 2>"
```

### 4. Bootstrap the OS

First run goes in as `root@` — `provision.sh` creates the `tayaway`
user, mirrors the authorized_keys, installs packages, writes the OS
configs, and reboots once if a kernel update came in.

```fish
mise run vm:provision root@<vps-hostname>
```

### 5. Hand-drop the age private key

Only manual secret-handling step in the whole recipe.

```fish
scp ~/.config/sops/age/keys.txt tayaway@new.tayaway.nl:/tmp/age.key
ssh tayaway@new.tayaway.nl 'sudo install -m 0400 -o root -g root /tmp/age.key /etc/tayaway/age.key && rm /tmp/age.key'
```

### 6. Re-run provision as tayaway

Verifies the age key is in place, syncs `quadlet/` (empty during Phase
3), reloads systemd. Idempotent — re-run any time you change anything
under `ops/`.

```fish
mise run vm:provision tayaway@new.tayaway.nl
```

### 7. (Phase 4 onward)

Once `quadlet/` has units in it, step 6 brings the stack alive. Cutover
to the apex is a separate Phase 7 PR.

## Total-loss recovery

The whole VPS is gone or unrecoverable.

1. **State bucket also gone:** `cd ops/bootstrap && tofu apply` — rare.
2. Order a new VPS-1 in the OVH manager (step 2 above).
3. `tofu apply -var "vps_ipv4=<new-ip>" …` to repoint `new.tayaway.nl`
   and recreate the WAL-G credentials.
4. scp the age key (step 5).
5. `mise run vm:provision` twice — `root@` then `tayaway@` (steps 4 + 6).
6. WAL-G restore (see `doc/operations/walg.md` — landing in Phase 5).

~20 min, four or five commands of human work plus the OVH-manager
order.

## Drift detection

`.github/workflows/ops-drift.yml` runs `tofu plan` on every PR that
touches `ops/**` and on a weekly schedule. A non-empty plan fails the
job. Catches "someone clicked something in the OVH console" before it
becomes invisible state.

The job uses a read-only OVH credential (`secrets.OVH_RO_*`), the
state-bucket S3 credentials (`secrets.OPS_STATE_S3_*`), and the
non-sensitive vars `OVH_PROJECT_ID` + `OPS_VPS_IPV4`. None of these
overlap with the production secrets the app reads at runtime — those
live only on the VPS in the sops-encrypted
`backend/.env.production.yaml` decrypted via the age key at
`/etc/tayaway/age.key`.

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
