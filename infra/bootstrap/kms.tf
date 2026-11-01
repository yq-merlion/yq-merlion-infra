# Bootstrap key: the bootstrap layer's own Terraform state only
data "aws_iam_policy_document" "bootstrap_key" {
  statement {
    sid       = "AccountAdminsViaIAM"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "bootstrap" {
  description             = "${var.project} bootstrap Terraform state"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.bootstrap_key.json
}

resource "aws_kms_alias" "bootstrap" {
  name          = "alias/${var.project}-bootstrap"
  target_key_id = aws_kms_key.bootstrap.key_id
}

# Audit key: the audit bucket (CloudTrail logs, deploy records). Kept separate from every state key,
# so access to the audit trail doesn't depend on who can read Terraform state.
data "aws_iam_policy_document" "audit_key" {
  statement {
    sid       = "AccountAdminsViaIAM"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudTrailEncrypt"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${local.account_id}:trail/*"]
    }
  }

  statement {
    sid       = "CloudTrailDescribe"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "audit" {
  description             = "${var.project} audit bucket and CloudTrail"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.audit_key.json
}

resource "aws_kms_alias" "audit" {
  name          = "alias/${var.project}-audit"
  target_key_id = aws_kms_key.audit.key_id
}

# One key per env state bucket. Pipeline access: only that env's CI role and the read-only plan role
# (iam-ci.tf); the other env's role is explicitly denied (guardrails.tf). Account admins keep access
# through IAM (AccountAdminsViaIAM) so the key can't be locked out.
data "aws_iam_policy_document" "state_key" {
  statement {
    sid       = "AccountAdminsViaIAM"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "state" {
  for_each = local.envs

  description             = "${var.project} ${each.key} Terraform state"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.state_key.json

  tags = {
    env = each.key
  }
}

resource "aws_kms_alias" "state" {
  for_each = local.envs

  name          = "alias/${var.project}-${each.key}-state"
  target_key_id = aws_kms_key.state[each.key].key_id
}
