# All knobs the operator sets at apply time. Sensible defaults where one
# exists; the rest (service_name, vps_ipv4) are required because they
# are deployment-specific and a wrong default would either fail loudly
# or — worse — silently provision against the wrong project / zone.

variable "ovh_endpoint" {
  type        = string
  description = "OVH API endpoint. `ovh-eu` is the European control plane."
  default     = "ovh-eu"
}

variable "service_name" {
  type        = string
  description = "OVH public cloud project ID. Required by the Object Storage resources even though the VPS itself isn't in a Public Cloud project — buckets, S3 users, and S3 policies all live under a cloud project."
}

variable "region_name" {
  type        = string
  description = "Short region name for Object Storage, e.g. `GRA`. The state bucket and the WAL-G bucket both live here."
  default     = "GRA"
}

# The VPS itself is ordered through the OVH manager (cheapest plan is
# VPS-1 at ~€6.68/month inc VAT; Public Cloud's hourly model puts an
# equivalent shape at >10× that price for a 24/7 workload). See
# README.md "Ordering the VPS" — the operator does the order once,
# then pastes the assigned IPv4 here so terraform can manage the
# DNS record that points at it.
variable "vps_ipv4" {
  type        = string
  description = "Public IPv4 of the new VPS, as shown in the OVH manager once the order completes. Used by ovh_domain_zone_record below."
}

variable "vps_ipv6" {
  type        = string
  description = "Public IPv6 of the new VPS (OVH assigns a single /128). Used for the new.tayaway.nl AAAA during commissioning and is what the apex AAAA flips to at cutover."
}

# Apex (tayaway.nl) current target. Defaults are the OLD box's live A/AAAA, so
# importing the apex records into state is a no-op and the drift check stays
# green during commissioning. The cutover flips these to the new box
# (var.vps_ipv4 / var.vps_ipv6) and lowers apex_ttl — see dns.tf.
variable "apex_ipv4" {
  type        = string
  description = "Current apex A target. New box as of the 2026-05-29 cutover."
  default     = "51.178.47.84"
}

variable "apex_ipv6" {
  type        = string
  description = "Current apex AAAA target. New box as of the 2026-05-29 cutover."
  default     = "2001:41d0:404:200::2460"
}

variable "apex_ttl" {
  type        = number
  description = "Apex record TTL. 0 = OVH zone default (resolves to 3600). Lowered to 300 ~24h before cutover so the apex flip propagates in minutes; flip the targets (apex_ipv4/apex_ipv6) once this short TTL has aged out everywhere."
  default     = 300
}

# DNS — we only manage records we are adding. The existing apex A record
# (tayaway.nl → old VPS) stays out of state until the cutover PR explicitly
# imports it, so a stray `tofu apply` cannot redirect production.
variable "domain" {
  type        = string
  description = "Apex domain registered at OVH."
  default     = "tayaway.nl"
}

variable "new_subdomain" {
  type        = string
  description = "Temporary hostname for the new VPS during commissioning, e.g. `new` → new.tayaway.nl. Used by Caddy's ACME and the staging e2e runs until the apex is cut over."
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
