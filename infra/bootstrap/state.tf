# Terraform state: one bucket and one KMS key per layer
#   yq-merlion-bootstrap-tfstate-<account>   this layer          key: alias/yq-merlion-bootstrap
#   yq-merlion-staging-tfstate-<account>     infra/envs/staging  key: alias/yq-merlion-staging-state
#   yq-merlion-prod-tfstate-<account>        infra/envs/prod     key: alias/yq-merlion-prod-state
# Each bucket holds a single terraform.tfstate (plus its .tflock while a run is in progress).

resource "aws_s3_bucket" "state" {
  for_each = local.state_buckets

  bucket = each.value.name

  # Lets the deny_other_env policy (guardrails.tf) block the other env's bucket by tag as well as by name
  tags = {
    env = each.value.env_tag
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  for_each = aws_s3_bucket.state

  bucket = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket default only. The S3 backend sends its own encryption setting on every upload, so each
# backend block must also set kms_key_id to the same key (otherwise it uploads with AES256).
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  for_each = aws_s3_bucket.state

  bucket = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      # bootstrap layer uses the bootstrap key; staging/prod use their own state key (kms.tf)
      kms_master_key_id = each.key == "bootstrap" ? aws_kms_key.bootstrap.arn : aws_kms_key.state[each.key].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  for_each = aws_s3_bucket.state

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  for_each = aws_s3_bucket.state

  bucket = each.value.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state_bucket" {
  for_each = aws_s3_bucket.state

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  for_each = aws_s3_bucket.state

  bucket = each.value.id
  policy = data.aws_iam_policy_document.state_bucket[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.state]
}
