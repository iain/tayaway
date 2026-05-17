# All knobs the operator sets at apply time. Sensible defaults where one
# exists; the rest (service_name, flavor_id, image_id, ssh keys, age key)
# are required because they are deployment-specific and a wrong default
# would either fail loudly or — worse — silently provision against the
# wrong project.

variable "ovh_endpoint" {
  type        = string
  description = "OVH API endpoint. `ovh-eu` is the European control plane."
  default     = "ovh-eu"
}

variable "service_name" {
  type        = string
  description = "OVH public cloud project ID."
}

variable "region" {
  type        = string
  description = "OVH region for the VM, e.g. `GRA11` or `SBG5`. Must be a region that hosts compute (not just storage)."
  default     = "GRA11"
}

variable "region_name" {
  type        = string
  description = "Short region name for Object Storage (e.g. `GRA`). Usually the compute region's prefix."
  default     = "GRA"
}

# Phase-3 deliverable: stand up a new VM *next to* the existing production
# VM without touching it. Same flavor / image / region so the two
# environments are like-for-like; cutover then becomes "swap DNS apex" and
# nothing else. Operator looks up the current prod VM's flavor and image
# IDs via the OVH manager or
#   ovh-cli cloud project <id> instance show <instance-id>
# and pastes them here.
variable "vm_flavor_id" {
  type        = string
  description = "OVH flavor UUID. Match the existing production VM exactly so the new stack sits on the same shape."
}

variable "vm_image_id" {
  type        = string
  description = "OVH image UUID — Ubuntu 24.04 LTS in the chosen region. Look up via `GET /cloud/project/{id}/image`."
}

variable "vm_name" {
  type        = string
  description = "Hostname for the new instance. Kept distinct from the existing prod VM so they cannot collide in OVH's namespace."
  default     = "tayaway-new"
}

variable "ssh_public_key" {
  type        = string
  description = "Operator's SSH public key. Uploaded as a new OVH keypair and attached to the instance for the initial provision."
}

variable "ssh_keypair_name" {
  type        = string
  description = "Name OVH stores the keypair under. Distinct from any existing keypair so the upload does not collide."
  default     = "tayaway-ops"
}

# DNS — we only manage records we are adding. The existing apex A record
# (tayaway.nl → old VM) stays out of state until the cutover PR explicitly
# imports it, so a stray `tofu apply` cannot redirect production.
variable "domain" {
  type        = string
  description = "Apex domain registered at OVH."
  default     = "tayaway.nl"
}

variable "new_subdomain" {
  type        = string
  description = "Temporary hostname for the new VM during commissioning, e.g. `new` → new.tayaway.nl. Used by Caddy's ACME and the staging e2e runs until the apex is cut over."
  default     = "new"
}

# WAL-G bucket — see ../doc on the migration plan. EU region, Standard
# tier; 1-month PITR window is enforced by WAL-G's retention, not at the
# bucket level (bucket lifecycle would conflict with base-backup pinning).
variable "walg_bucket_name" {
  type        = string
  description = "Name of the WAL-G backup bucket. Globally unique within OVH Object Storage."
  default     = "tayaway-walg"
}

variable "age_recipient" {
  type        = string
  description = "Age public key the sops-encrypted secrets are encrypted to. Surfaces in `outputs.tf` for the operator to compare against ~/.config/sops/age/keys.txt."
}
