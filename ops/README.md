# ops/

Declarative recipe for tayaway's production infrastructure. Three layers,
each tracked in git:

| Layer                | What it owns                                                                                 | Where                                |
| -------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------ |
| Cloud-level state    | OVH project resources: VM, DNS, WAL-G bucket, state bucket                                   | `*.tf`, `bootstrap/*.tf`             |
| First-boot bootstrap | OS-level setup that only runs once: podman, tayaway user, journald caps, nftables baseline   | `cloud-init.yaml`                    |
| App-side state       | Iterable bits: quadlet units, image pre-pulls, daemon-reloads                                | `provision.sh`, `quadlet/`           |

Cloud-init can't be re-run; `provision.sh` is the thing you edit and
re-apply.

## What this Phase 3 PR ships

A complete recipe — `tofu apply` brings up a fresh VM next to the
existing production VM without touching it. Phase 4 fills in `quadlet/`
with the actual unit files; Phase 7 (cutover) flips DNS.

The deliberate gap: the existing apex `tayaway.nl` A record is **not** in
this config. `ovh_domain_zone_record` is per-record, so leaving it out
means `tofu apply` cannot redirect production while the new stack is
being commissioned. Cutover imports it explicitly.

## First-time apply on an empty OVH project

You need: OVH API credentials with permissions on the target Public
Cloud project, an age keypair, and an ssh public key.

```bash
# 1. Bootstrap the state bucket. Local terraform.tfstate is gitignored —
#    back it up to wherever your laptop secrets live.
cd ops/bootstrap
export OVH_APPLICATION_KEY=…
export OVH_APPLICATION_SECRET=…
export OVH_CONSUMER_KEY=…
tofu init
tofu apply -var "service_name=<project-id>"

# 2. Capture the credentials it printed and use them for the main
#    config's S3 backend. Both vars go into your shell, not into git.
#    Note: if you overrode `bucket_name` or `region_name` in step 1, also
#    update `bucket` / `region` / `endpoints.s3` in ops/providers.tf —
#    Terraform backends can't read variables, so those names are
#    hardcoded.
export AWS_ACCESS_KEY_ID=$(tofu output -raw state_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(tofu output -raw state_secret_access_key)

# 3. Look up the existing prod VM's flavor + image IDs so the new VM
#    matches like-for-like. (Replace <project-id>.)
ovhcli --format=json cloud project <project-id> instance | jq '.[] | {name, flavorId, imageId, region}'

# 4. Apply the main config. age_recipient is the *public* key from
#    `age-keygen -y < ~/.config/sops/age/keys.txt`.
cd ..
tofu init
tofu apply \
  -var "service_name=<project-id>" \
  -var "vm_flavor_id=<from step 3>" \
  -var "vm_image_id=<from step 3>" \
  -var "ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)" \
  -var "age_recipient=age1…"

# 5. Hand-drop the age private key onto the new VM. Only manual step.
IP=$(tofu output -raw vm_public_ipv4)
scp ~/.config/sops/age/keys.txt tayaway@$IP:/tmp/age.key
ssh tayaway@$IP 'sudo install -m 0400 -o root -g root /tmp/age.key /etc/tayaway/age.key && rm /tmp/age.key'

# 6. Run the app-side provisioner. Idempotent — re-run on every change.
mise run vm:provision tayaway@$IP

# 7. (Phase 4) Once quadlet/ has units in it, re-run step 6 to pick
#    them up and let the stack come alive.
```

## Total-loss recovery

OVH project is gone or unreachable. Recovery is the same sequence as
first-time apply, except for the bootstrap step which is skipped when
the state bucket already exists.

1. **State bucket also gone:** `cd ops/bootstrap && tofu apply` — rare;
   only if a project rebuild wiped Object Storage.
2. `tofu apply` against the main config — VM, DNS, buckets come back.
3. scp the age key (step 5 above).
4. `mise run vm:provision <new-host>` (step 6 above).
5. WAL-G restore (see `doc/operations/walg.md` — landing in Phase 5).

~15 min of automation, three or four commands of human work.

## Drift detection

A GitHub Actions job (`.github/workflows/ops-drift.yml`) runs
`tofu plan` on every PR that touches `ops/**` and on a weekly schedule.
A non-empty plan fails the job. This is what catches "someone clicked
something in the OVH console" before it becomes invisible state.

The job uses a read-only OVH credential (`secrets.OVH_RO_*`) plus the
state-bucket S3 credentials (`secrets.OPS_STATE_S3_*`). Neither overlaps
with the production secrets the app reads at runtime — those live only
on the VM in the sops-encrypted `.env.production.yaml` decrypted via the
age key at `/etc/tayaway/age.key`.

## Annual full-provisioning drill

`tofu apply -var "vm_name=tayaway-drill"` against a throwaway VM once a
year, then `tofu destroy`. Catches drift in `cloud-init.yaml` /
`provision.sh` that the per-PR drift-detection job can't see (cloud-init
runs only on first boot; the drift job never exercises it). Belongs in
the calendar, not this ticket.

## Why not Ansible / Chef / etc.

The whole point is "rebuild from a short recipe, not a memorised dance."
Three files (`cloud-init.yaml`, `provision.sh`, `*.tf`) plus the quadlet
units fits in one head and reads in one sitting; pulling in a
configuration-management framework would obscure that for a one-VM
deployment whose configuration is already trivially declarative.
