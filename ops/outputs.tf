# Everything the operator (and the Phase-4 quadlet units) need to know
# about the deployed infra. Sensitive values only appear via
# `tofu output -raw <name>` — they don't render in `tofu apply`'s
# summary.

output "vps_ipv4" {
  description = "Public IPv4 of the VPS — echoed back so the operator can confirm the right value made it into the DNS records."
  value       = var.vps_ipv4
}

output "vps_hostname" {
  description = "Public hostname the VPS serves. Caddy provisions ACME certs for this name (and www)."
  value       = var.domain
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
  description = "S3 access key id for WAL-G. sops it into backend/.env.production.yaml as WALG_S3_ACCESS_KEY_ID (the db-secret oneshot maps it to AWS_ACCESS_KEY_ID inside the db container, keeping it out of the web app's env)."
  value       = ovh_cloud_project_user_s3_credential.walg.access_key_id
}

output "walg_secret_access_key" {
  description = "S3 secret key for WAL-G. Read with `tofu output -raw walg_secret_access_key`, then `sops` it into backend/.env.production.yaml as WALG_S3_SECRET_ACCESS_KEY."
  value       = ovh_cloud_project_user_s3_credential.walg.secret_access_key
  sensitive   = true
}
