# WAL-G backup bucket. Standard tier, EU region — free egress, ~€0.007 /
# GiB / month. WAL-G writes continuous WAL plus a weekly base + daily
# delta; the retention policy lives in WAL-G config (1-month window),
# *not* a bucket lifecycle rule, because base-backup pinning would
# conflict with object expiry.
#
# Encryption: SSE-AES256 at rest in OVH, plus WAL-G's own libsodium
# envelope encryption with WALG_LIBSODIUM_KEY (in sops, not here). Two
# independent layers — if OVH's at-rest encryption is ever turned off,
# the WAL-G layer still protects the dumps.

resource "ovh_cloud_project_storage" "walg" {
  service_name = var.service_name
  region_name  = var.region_name
  name         = var.walg_bucket_name

  versioning = {
    status = "enabled"
  }

  encryption = {
    sse_algorithm = "AES256"
  }
}

# Dedicated user with object-store-only role so a leaked WAL-G credential
# cannot touch compute, networks, or DNS records.
resource "ovh_cloud_project_user" "walg" {
  service_name = var.service_name
  description  = "WAL-G backup access (managed by ops/)"
  role_names   = ["objectstore_operator"]
}

resource "ovh_cloud_project_user_s3_credential" "walg" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.walg.id
}

# Limit the user to *this* bucket only. WAL-G needs the full RW set on
# objects plus ListBucketMultipartUploads for resumable uploads of large
# WAL segments.
resource "ovh_cloud_project_user_s3_policy" "walg" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.walg.id

  policy = jsonencode({
    Statement = [{
      Sid    = "WalgBucketRW"
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:ListMultipartUploadParts",
        "s3:ListBucketMultipartUploads",
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
      ]
      Resource = [
        "arn:aws:s3:::${var.walg_bucket_name}",
        "arn:aws:s3:::${var.walg_bucket_name}/*",
      ]
    }]
  })
}
