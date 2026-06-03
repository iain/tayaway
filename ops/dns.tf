# DNS records this config owns.
#
# We deliberately leave OVH's auto-generated zone infrastructure UNMANAGED, so a
# stray `tofu apply` can't touch it:
#   - the apex NS records (dns14/ns14.ovh.net)
#   - the default `ftp` CNAME
#   - OVH's web-redirection marker TXTs (`1|…` at the apex, `3|welcome` at www)
#
# Everything meaningful is adopted below: the apex + www A/AAAA pointing at our
# box, and the OVH-email cluster (MX, SPF, DKIM, DMARC, autodiscover SRV).
#
# Records that already exist in the zone must be `tofu import`ed before the
# first apply that declares them, or tofu will try to create duplicates. The
# OVH provider's import id is "<recordID>.<zone>" (record id first, dotted — NOT
# "<zone>/<recordID>"). Find ids via the OVH API:
#   GET /domain/zone/tayaway.nl/record           # all ids
#   GET /domain/zone/tayaway.nl/record/<id>      # one record
# See ops/README.md for the full recipe.

# ── Apex: tayaway.nl → our box ────────────────────────────────────────────────
resource "ovh_domain_zone_record" "apex_a" {
  zone      = var.domain
  subdomain = ""
  fieldtype = "A"
  ttl       = var.apex_ttl
  target    = var.vps_ipv4
}

resource "ovh_domain_zone_record" "apex_aaaa" {
  zone      = var.domain
  subdomain = ""
  fieldtype = "AAAA"
  ttl       = var.apex_ttl
  target    = var.vps_ipv6
}

# ── www.tayaway.nl → our box ──────────────────────────────────────────────────
# The edge Caddy serves www and 301-redirects it to the apex (see the
# www-redirect block in containers/Caddyfile, switched on by WWW_SITE_ADDRESS on
# edge.container). Dual-stack to match the apex, so a v6-only client can reach
# the redirect too.
resource "ovh_domain_zone_record" "www_a" {
  zone      = var.domain
  subdomain = "www"
  fieldtype = "A"
  ttl       = 0
  target    = var.vps_ipv4
}

resource "ovh_domain_zone_record" "www_aaaa" {
  zone      = var.domain
  subdomain = "www"
  fieldtype = "AAAA"
  ttl       = 0
  target    = var.vps_ipv6
}

# ── OVH-hosted email ──────────────────────────────────────────────────────────
# MX + SPF + DKIM selectors + DMARC + autodiscover SRV for the OVH mailbox on
# tayaway.nl. Adopted so the mail config is reviewable and rebuildable; the
# targets are OVH's and don't change. ttl = 0 means "OVH zone default" (3600),
# matching how OVH created them.
resource "ovh_domain_zone_record" "mx" {
  for_each = {
    mx0 = "1 mx0.mail.ovh.net."
    mx1 = "5 mx1.mail.ovh.net."
    mx2 = "50 mx2.mail.ovh.net."
    mx3 = "100 mx3.mail.ovh.net."
  }
  zone      = var.domain
  subdomain = ""
  fieldtype = "MX"
  ttl       = 0
  target    = each.value
}

resource "ovh_domain_zone_record" "spf" {
  zone      = var.domain
  subdomain = ""
  fieldtype = "SPF"
  ttl       = 0
  target    = "v=spf1 include:mx.ovh.com ~all"
}

resource "ovh_domain_zone_record" "dkim" {
  for_each = {
    "ovhmo-selector-1._domainkey" = "ovhmo-selector-1._domainkey.4465666.hs.dkim.mail.ovh.net."
    "ovhmo-selector-2._domainkey" = "ovhmo-selector-2._domainkey.4465667.hs.dkim.mail.ovh.net."
  }
  zone      = var.domain
  subdomain = each.key
  fieldtype = "CNAME"
  ttl       = 0
  target    = each.value
}

resource "ovh_domain_zone_record" "dmarc" {
  zone      = var.domain
  subdomain = "_dmarc"
  fieldtype = "DMARC"
  ttl       = 0
  target    = "v=DMARC1; p=none; rua=mailto:noreply@tayaway.nl; sp=none; aspf=r"
}

resource "ovh_domain_zone_record" "autodiscover" {
  zone      = var.domain
  subdomain = "_autodiscover._tcp"
  fieldtype = "SRV"
  ttl       = 0
  target    = "0 0 443 zimbra1.mail.ovh.net."
}
