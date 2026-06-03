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
# then pastes the assigned IPs here so terraform can manage the DNS
# records (apex + www) that point at it.
variable "vps_ipv4" {
  type        = string
  description = "Public IPv4 of the VPS, as shown in the OVH manager once the order completes. Target of the apex + www A records."
}

variable "vps_ipv6" {
  type        = string
  description = "Public IPv6 of the VPS (OVH assigns a single /128). Target of the apex + www AAAA records."
}

variable "apex_ttl" {
  type        = number
  description = "Apex record TTL in seconds. 0 = OVH zone default (resolves to 3600). Lowered to 300 for the 2026-05-29 cutover so the apex flip propagated in minutes; left there since it's harmless and keeps future flips quick."
  default     = 300
}

variable "domain" {
  type        = string
  description = "Apex domain registered at OVH."
  default     = "tayaway.nl"
}

# WAL-G bucket — see ../doc on the migration plan. EU region, Standard
# tier; 1-month PITR window is enforced by WAL-G's retention, not at the
# bucket level (bucket lifecycle would conflict with base-backup pinning).
variable "walg_bucket_name" {
  type        = string
  description = "Name of the WAL-G backup bucket. Globally unique within OVH Object Storage."
  default     = "tayaway-walg"
}
