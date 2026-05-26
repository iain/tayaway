# DNS records this config owns.
#
# During commissioning we own only the `new.tayaway.nl` A/AAAA records, so a
# stray `tofu apply` cannot redirect production. The apex (`tayaway.nl`)
# resources below are defined for the Phase-7 cutover but are NOT in state
# until explicitly imported (see the apex block) — until then tofu neither
# manages nor can disturb them.

# ── Commissioning host: new.tayaway.nl ───────────────────────────────────────
# Public hostname for Caddy's ACME cert and the e2e suite during
# commissioning. Both A and AAAA so the box is reachable over IPv4 and IPv6
# (Caddy answers on both; a v6-only client otherwise can't reach it). 5-minute
# TTL so the records can be torn down quickly after cutover. Removed in the
# cutover PR once the apex is live.
resource "ovh_domain_zone_record" "new_a" {
  zone      = var.domain
  subdomain = var.new_subdomain
  fieldtype = "A"
  ttl       = 300
  target    = var.vps_ipv4
}

resource "ovh_domain_zone_record" "new_aaaa" {
  zone      = var.domain
  subdomain = var.new_subdomain
  fieldtype = "AAAA"
  ttl       = 300
  target    = var.vps_ipv6
}

# ── Apex cutover (Phase 7) ────────────────────────────────────────────────────
# tayaway.nl A + AAAA already exist in OVH pointing at the OLD box. These
# resources ADOPT them — so before the first apply that includes them they
# MUST be imported, or tofu will try to create duplicates:
#
#   1. Find the existing record IDs (same OVH creds tofu uses, loaded by
#      ops/mise.toml). The apex is the empty subdomain:
#        mise exec -- bash -c 'source <(...) ...'   # or via the OVH API:
#        GET /domain/zone/tayaway.nl/record?fieldType=A&subDomain=
#        GET /domain/zone/tayaway.nl/record?fieldType=AAAA&subDomain=
#   2. Import each (OVH import id is "<zone>/<recordID>"):
#        mise exec -- tofu import ovh_domain_zone_record.apex_a    tayaway.nl/<ID_A>
#        mise exec -- tofu import ovh_domain_zone_record.apex_aaaa tayaway.nl/<ID_AAAA>
#   3. `tofu plan` now shows the diff between the live records (old box,
#      TTL 3600) and the desired state below (new box, TTL 300) — i.e. the
#      cutover itself. Nothing is applied until you choose to.
#
# Targets default to the OLD box (var.apex_ipv4/apex_ipv6) and TTL to 3600,
# matching the live records — so once imported the plan is empty and the
# drift check stays green right up to cutover.
#
# Cutover sequence:
#   ~24h before:  set apex_ttl = 300, apply   # TTL only; still points at old
#   at cutover:   set apex_ipv4 = var.vps_ipv4 value, apex_ipv6 = var.vps_ipv6
#                 value, apply                 # flips apex A+AAAA to the new box
# then watch resolvers pick it up, keep the old box warm a week, and remove
# the new.tayaway.nl records above in a follow-up.
resource "ovh_domain_zone_record" "apex_a" {
  zone      = var.domain
  subdomain = ""
  fieldtype = "A"
  ttl       = var.apex_ttl
  target    = var.apex_ipv4
}

resource "ovh_domain_zone_record" "apex_aaaa" {
  zone      = var.domain
  subdomain = ""
  fieldtype = "AAAA"
  ttl       = var.apex_ttl
  target    = var.apex_ipv6
}
