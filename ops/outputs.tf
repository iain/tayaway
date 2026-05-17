# Everything the operator (and the Phase-4 quadlet units) need to know
# about the deployed infra. Sensitive values only appear via
# `tofu output -raw <name>` — they don't render in `tofu apply`'s
# summary.

output "vm_public_ipv4" {
  description = "IPv4 address of the new VM. Use for `mise run vm:provision <ip>` and `ssh tayaway@<ip>`."
  value       = local.public_ipv4
}

output "vm_hostname" {
  description = "Temporary public hostname for the new VM. Caddy provisions an ACME cert for this name during commissioning."
  value       = "${var.new_subdomain}.${var.domain}"
}

output "walg_bucket" {
  description = "S3 bucket name for WAL-G."
  value       = ovh_cloud_project_storage.walg.name
}

output "walg_endpoint" {
  description = "S3 endpoint for the WAL-G bucket's region. Goes into WALG_S3_PREFIX / AWS_ENDPOINT_FORCE_PATH_STYLE in the walg.container env."
  value       = "https://s3.${lower(var.region_name)}.io.cloud.ovh.net"
}

output "walg_access_key_id" {
  description = "S3 access key id for WAL-G. Encrypt with sops into backend/.env.production.yaml as AWS_ACCESS_KEY_ID."
  value       = ovh_cloud_project_user_s3_credential.walg.access_key_id
}

output "walg_secret_access_key" {
  description = "S3 secret key for WAL-G. Read with `tofu output -raw walg_secret_access_key`, then `sops` it into backend/.env.production.yaml as AWS_SECRET_ACCESS_KEY."
  value       = ovh_cloud_project_user_s3_credential.walg.secret_access_key
  sensitive   = true
}

output "age_recipient_echo" {
  description = "Confirms which age public key the VM expects. Compare against the recipient line in backend/.env.production.yaml."
  value       = var.age_recipient
}
