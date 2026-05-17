terraform {
  required_version = ">= 1.6.0"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.0"
    }
  }

  # OVH Object Storage is S3-compatible; OpenTofu's S3 backend talks to it
  # over the same wire. Bucket / endpoint / region come from ../bootstrap;
  # access_key + secret_key are supplied via env vars (AWS_ACCESS_KEY_ID,
  # AWS_SECRET_ACCESS_KEY) so this file stays credential-free and safe to
  # commit. OVH's S3 doesn't support DynamoDB-style locking, so we set
  # skip_credentials_validation + skip_metadata_api_check + skip_region_validation
  # to keep the AWS-specific preflights from failing against the OVH endpoint.
  backend "s3" {
    bucket = "tayaway-tfstate"
    key    = "ops/main.tfstate"
    region = "gra"

    endpoints = {
      s3 = "https://s3.gra.io.cloud.ovh.net"
    }

    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

provider "ovh" {
  endpoint = var.ovh_endpoint
}
