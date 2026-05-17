# A single Public Cloud instance for the new stack. Phase 4 brings up the
# quadlet units on top of it; Phase 7 cuts the apex DNS over. Until then
# this VM coexists with the legacy one — different name, different IP,
# different (temporary) hostname.
#
# `ssh_key_create` uploads the operator's public key as a fresh OVH keypair
# instead of referencing an existing keypair by name. Keeps the recipe
# self-contained: a clean OVH project + `tofu apply` works without any
# manual console clicks first.

resource "ovh_cloud_project_instance" "web" {
  service_name   = var.service_name
  region         = var.region
  billing_period = "hourly"
  name           = var.vm_name

  flavor {
    flavor_id = var.vm_flavor_id
  }

  boot_from {
    image_id = var.vm_image_id
  }

  network {
    public = true
  }

  ssh_key_create {
    name       = var.ssh_keypair_name
    public_key = var.ssh_public_key
  }

  # Rendered cloud-init. The age recipient is templated in so the VM can
  # later verify it has been given the matching private key (the recipient
  # public key gets written to /etc/tayaway/age.recipient at first boot).
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    age_recipient = var.age_recipient
  })

  # Fail loudly during apply if the provider returns no IPv4 — better
  # than the bare `[0]` below tripping over an empty list with an
  # opaque "index out of range" message.
  lifecycle {
    postcondition {
      condition     = length([for a in self.addresses : a if tostring(a.version) == "4"]) > 0
      error_message = "OVH instance returned no IPv4 address. Check the OVH manager and `tofu state show ovh_cloud_project_instance.web`."
    }
  }
}

# The instance returns several addresses (IPv4 + IPv6 public, and any
# private NICs we add later). Pick the first public IPv4 for DNS and for
# the provisioning script. Sticking with IPv4 avoids surprises with hosts
# whose ISPs are IPv6-flaky and matches what the legacy VM serves on.
#
# `tostring(a.version)` shields against the OVH provider returning the
# version as either a number (4) or a string ("4") — its docs don't
# pin the type, and getting this wrong only surfaces at apply time.
locals {
  public_ipv4 = [
    for a in ovh_cloud_project_instance.web.addresses :
    a.ip if tostring(a.version) == "4"
  ][0]
}
