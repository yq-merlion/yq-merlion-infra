# Explicit Deny statements shared by the CI roles and the workload permissions boundaries.
# An explicit Deny always wins, so these hold even if an Allow elsewhere is too broad.

locals {
  r = var.region
  a = var.account_id
  p = var.project

  # Resources owned by one environment, identified by name. Used to deny the *other* env.
  env_named_arns = { for e in ["staging", "prod"] : e => [
    "arn:aws:s3:::${local.p}-${e}-*",
    "arn:aws:s3:::${local.p}-${e}-*/*",
    # EKS: cluster/<name>, nodegroup/<name>/..., addon/..., access-entry/..., podidentityassociation/...
    "arn:aws:eks:${local.r}:${local.a}:*/${local.p}-${e}*",
    # RDS: db:, subgrp:, pg:, og:, snapshot:, snapshot:rds: (the * also matches the colons)
    "arn:aws:rds:${local.r}:${local.a}:*:${local.p}-${e}*",
    "arn:aws:iam::${local.a}:role/${local.p}-${e}-*",
    "arn:aws:iam::${local.a}:policy/${local.p}-${e}-*",
    "arn:aws:secretsmanager:${local.r}:${local.a}:secret:${local.p}/${e}/*",
    "arn:aws:logs:${local.r}:${local.a}:log-group:/aws/eks/${local.p}-${e}/*",
    "arn:aws:logs:${local.r}:${local.a}:log-group:/${local.p}/${e}/*",
    "arn:aws:sns:${local.r}:${local.a}:${local.p}-${e}-*",
    "arn:aws:firehose:${local.r}:${local.a}:deliverystream/${local.p}-${e}-*",
    "arn:aws:cloudwatch:${local.r}:${local.a}:alarm:${local.p}-${e}-*",
  ] }

  ci_role_names = {
    ecr_push = "${local.p}-ci-ecr-push"
    plan     = "${local.p}-ci-plan"
    staging  = "${local.p}-ci-staging"
    prod     = "${local.p}-ci-prod"
  }

  boundary_arns = { for e in ["staging", "prod"] :
    e => "arn:aws:iam::${local.a}:policy/${local.p}-${e}-workload-boundary"
  }

  ecr_repo_arn = "arn:aws:ecr:${local.r}:${local.a}:repository/${local.p}/*"
}

# Protects the bootstrap layer: state and audit buckets, the trail, CI roles, boundaries, the KMS
# keys and ECR repos. Nothing created by the pipeline can weaken the audit trail or its own permissions.
data "aws_iam_policy_document" "protect_bootstrap" {
  statement {
    sid    = "DenyBucketConfigChanges"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketObjectLockConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketAcl",
      "s3:PutBucketOwnershipControls",
      "s3:PutReplicationConfiguration",
    ]
    resources = concat(
      [for b in values(local.state_buckets) : "arn:aws:s3:::${b.name}"],
      ["arn:aws:s3:::${local.audit_bucket}"],
    )
  }

  # The pipeline roles never need the bootstrap layer's own state
  statement {
    sid       = "DenyBootstrapState"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${local.state_buckets.bootstrap.name}", "arn:aws:s3:::${local.state_buckets.bootstrap.name}/*"]
  }

  # Pipeline roles never use the bootstrap state key
  statement {
    sid       = "DenyBootstrapKey"
    effect    = "Deny"
    actions   = ["kms:*"]
    resources = [aws_kms_key.bootstrap.arn]
  }

  # The audit key may only be used to write to the audit bucket (deploy records). The audit bucket
  # uses an S3 bucket key, so S3 sends the bucket ARN as the encryption context. A missing context
  # also counts as "not equal", so direct use of the key is denied too.
  statement {
    sid    = "AuditKeyAuditBucketOnly"
    effect = "Deny"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = [aws_kms_key.audit.arn]
    condition {
      test     = "StringNotEquals"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = ["arn:aws:s3:::${local.audit_bucket}"]
    }
  }

  # Write deploy records, never read the audit trail back
  statement {
    sid       = "DenyReadingAuditLogs"
    effect    = "Deny"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["arn:aws:s3:::${local.audit_bucket}/*"]
  }

  statement {
    sid    = "DenyAuditTampering"
    effect = "Deny"
    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:PutObjectRetention",
      "s3:PutObjectLegalHold",
      "s3:BypassGovernanceRetention",
    ]
    resources = ["arn:aws:s3:::${local.audit_bucket}/*"]
  }

  statement {
    sid    = "DenyTrailChanges"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:PutInsightSelectors",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyKeyAdminOnMerlionKeys"
    effect = "Deny"
    actions = [
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:CreateGrant",
      "kms:UpdateKeyDescription",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:DeleteAlias",
      "kms:UpdateAlias",
    ]
    resources = concat(
      [aws_kms_key.bootstrap.arn, "arn:aws:kms:${local.r}:${local.a}:alias/${local.p}-bootstrap"],
      [aws_kms_key.audit.arn, "arn:aws:kms:${local.r}:${local.a}:alias/${local.p}-audit"],
      [for e, k in aws_kms_key.state : k.arn],
      [for e in keys(local.envs) : "arn:aws:kms:${local.r}:${local.a}:alias/${local.p}-${e}-state"],
    )
  }

  statement {
    sid     = "DenyChangesToCIRolesAndBoundaries"
    effect  = "Deny"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${local.a}:role/${local.p}-ci-*",
      "arn:aws:iam::${local.a}:policy/${local.p}-ci-*",
      "arn:aws:iam::${local.a}:policy/${local.p}-*-workload-boundary",
    ]
  }

  statement {
    sid       = "DenyRemovingBoundaries"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyEcrRepoChanges"
    effect = "Deny"
    actions = [
      "ecr:DeleteRepository",
      "ecr:DeleteRepositoryPolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:PutLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:PutImageTagMutability",
      "ecr:PutImageScanningConfiguration",
      "ecr:BatchDeleteImage",
    ]
    resources = [local.ecr_repo_arn]
  }

  # KMS keys in this shared account mostly delegate to IAM, so stop destructive key actions on any
  # key that isn't ours. An untagged key also matches (missing tag = "not merlion").
  statement {
    sid    = "DenyKeyAdminOnOtherProjects"
    effect = "Deny"
    actions = [
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
      "kms:PutKeyPolicy",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/project"
      values   = [local.p]
    }
  }
}

# Environment separation: deny everything that belongs to the other env, by tag and by name
data "aws_iam_policy_document" "deny_other_env" {
  for_each = local.envs

  statement {
    sid       = "DenyOtherEnvByResourceTag"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/env"
      values   = [each.value.other]
    }
  }

  statement {
    sid       = "DenyCreatingOtherEnvTags"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/env"
      values   = [each.value.other]
    }
  }

  statement {
    sid       = "DenyOtherEnvByName"
    effect    = "Deny"
    actions   = ["*"]
    resources = local.env_named_arns[each.value.other]
  }

  # Each env's state has its own KMS key. Never use the other env's key.
  statement {
    sid       = "DenyOtherEnvStateKey"
    effect    = "Deny"
    actions   = ["kms:*"]
    resources = [aws_kms_key.state[each.value.other].arn]
  }
}
