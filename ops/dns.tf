# DNS records this config owns.
#
# Post-cutover (2026-05-29): the apex (`tayaway.nl`) A/AAAA are imported into
# state and point at the new box — they serve production. The `new.tayaway.nl`
# A/AAAA below are a now-redundant commissioning leftover, still live; they get
# dropped in the post-cutover DNS cleanup (a `tofu apply`, not just a config
# edit, so the drift check stays green).

# ── Commissioning host: new.tayaway.nl ───────────────────────────────────────
# Public hostname for Caddy's ACME cert and the e2e suite during
# commissioning. Both A and AAAA so the box is reachable over IPv4 and IPv6
# (Caddy answers on both; a v6-only client otherwise can't reach it). 5-minute
# TTL so the records can be torn down quickly after cutover. Redundant now that
# the apex serves production — pending removal in the post-cutover DNS cleanup.
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
#   2. Import each. The OVH provider's import id is "<recordID>.<zone>"
#      (record id first, dotted — NOT "<zone>/<recordID>"):
#        mise exec -- tofu import ovh_domain_zone_record.apex_a    <ID_A>.tayaway.nl
#        mise exec -- tofu import ovh_domain_zone_record.apex_aaaa <ID_AAAA>.tayaway.nl
#   3. `tofu plan` is then empty — the adopted records match the config below.
#
# (Already imported as of the 2026-05-26 cutover-prep session; this is the
# recipe for a rebuild.)
#
# Post-cutover, var.apex_ipv4/apex_ipv6 default to the NEW box and apex_ttl is
# 300 (see variables.tf), matching the live records — so the plan stays empty
# and the drift check green. Before cutover these defaulted to the old box; the
# sequence below is kept as the rebuild recipe.
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
