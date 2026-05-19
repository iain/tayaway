# Bootstrap config — creates the OVH Object Storage bucket that the main
# ops/ config uses as its remote state backend. State for *this* config
# lives on the operator's laptop (terraform.tfstate, gitignored); it is
# only ever touched when the state bucket needs to be created, replaced,
# or audited, so it is backed up out-of-band rather than chained behind
# another bucket. Sidesteps the chicken-and-egg of "where does the state
# bucket's state live".
#
# Total-loss recovery: only re-run this if the state bucket itself is
# gone. In every other scenario you go straight to `tofu apply` in
# ../ against the existing bucket.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.0"
    }
  }
}

provider "ovh" {
  endpoint = var.ovh_endpoint
}

# S3-compatible "Standard" object storage. Versioning is on so a
# fat-fingered local `tofu destroy` or a corrupted state push can be
# rolled back from a previous object version.
resource "ovh_cloud_project_storage" "tfstate" {
  service_name = var.service_name
  region_name  = var.region_name
  name         = var.bucket_name

  versioning = {
    status = "enabled"
  }

  encryption = {
    sse_algorithm = "AES256"
  }
}

# Dedicated OVH project user with object-store-only role, so a leaked
# state-bucket credential cannot touch VMs, networks, or DNS records.
resource "ovh_cloud_project_user" "tfstate" {
  service_name = var.service_name
  description  = "Terraform state bucket access (managed by ops/bootstrap)"
  role_names   = ["objectstore_operator"]
}

resource "ovh_cloud_project_user_s3_credential" "tfstate" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.tfstate.id
}

resource "ovh_cloud_project_user_s3_policy" "tfstate" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.tfstate.id

  # Versioning is on at the bucket level for recovery from a corrupt
  # state push, but OVH's IAM grammar doesn't yet accept the
  # per-version actions (`s3:GetObjectVersion`, `s3:DeleteObjectVersion`)
  # — recovery goes through the OVH manager / AWS CLI as a human-driven
  # step, not via this credential. The credential needs `ListBucketVersions`
  # so a human running `aws s3api list-object-versions` from the laptop can
  # find the version id to restore.
  policy = jsonencode({
    Statement = [{
      Sid    = "TfStateBucketRW"
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListBucketVersions",
      ]
      Resource = [
        "arn:aws:s3:::${var.bucket_name}",
        "arn:aws:s3:::${var.bucket_name}/*",
      ]
    }]
  })
}

# Echo the bits the operator needs to configure the main config's S3
# backend. secret_access_key is sensitive so it only appears via
# `tofu output -raw state_secret_access_key`.

output "state_bucket_name" {
  value = ovh_cloud_project_storage.tfstate.name
}

output "state_region_name" {
  value = var.region_name
}

output "state_endpoint" {
  description = "S3 endpoint for the chosen region — pass to the backend `endpoint` setting."
  value       = "https://s3.${lower(var.region_name)}.io.cloud.ovh.net"
}

output "state_access_key_id" {
  value = ovh_cloud_project_user_s3_credential.tfstate.access_key_id
}

output "state_secret_access_key" {
  value     = ovh_cloud_project_user_s3_credential.tfstate.secret_access_key
  sensitive = true
}
