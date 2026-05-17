# DNS records this config owns. The apex (`tayaway.nl` A → old VPS) is
# deliberately *not* in here — `ovh_domain_zone_record` is per-record, so
# leaving the apex out of state means a `tofu apply` cannot redirect
# production while the new stack is being commissioned.
#
# The cutover PR (Phase 7) will:
#   1. Add an `ovh_domain_zone_record` for the apex pointing at the new IP.
#   2. `tofu import` the existing OVH record ID into that resource so the
#      apply is a no-op until the IP is actually flipped.
#   3. Update the IP, apply, watch TTL expiry, then remove the
#      `new.tayaway.nl` record below.

# Temporary public hostname for Caddy to provision an ACME cert against
# and for the e2e suite to run against during commissioning. 5-minute TTL
# so the record can be torn down quickly after cutover without leaving
# clients caching it. IP comes from a variable because the VPS itself is
# ordered outside terraform — see README "Ordering the VPS".
resource "ovh_domain_zone_record" "new_a" {
  zone      = var.domain
  subdomain = var.new_subdomain
  fieldtype = "A"
  ttl       = 300
  target    = var.vps_ipv4
}
