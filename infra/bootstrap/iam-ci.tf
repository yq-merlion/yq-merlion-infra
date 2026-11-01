# GitHub Actions roles. Each one can only be assumed by one exact workflow identity (see oidc.tf).
#
#   merlion-ci-ecr-push  yq-merlion-app, main branch      push images to ECR, nothing else
#   merlion-ci-plan      yq-merlion-infra, pull requests  read-only: terraform plan, digest checks
#   merlion-ci-staging   yq-merlion-infra, env staging    change staging only
#   merlion-ci-prod      yq-merlion-infra, env production change prod only (after approval)

resource "aws_iam_role" "ci" {
  for_each = local.ci_role_names

  name                 = each.value
  assume_role_policy   = data.aws_iam_policy_document.github_trust[each.key].json
  max_session_duration = 3600
}

# --- ecr-push ---------------------------------------------------------------------------------

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushAndReadMerlionImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [local.ecr_repo_arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.ci["ecr_push"].id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# --- plan (read-only) ---------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.ci["plan"].name
  policy_arn = local.read_only_arn
}

data "aws_iam_policy_document" "plan" {
  # Plans take the state lock, so allow only the lock files. State itself stays read-only.
  statement {
    sid       = "StateLockFilesOnly"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = [for b in values(local.state_buckets) : "arn:aws:s3:::${b.name}/*.tflock"]
  }

  statement {
    sid       = "UseStateKeys"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = concat([aws_kms_key.bootstrap.arn], [for e, k in aws_kms_key.state : k.arn])
  }

  # ReadOnlyAccess can read every bucket. Keep the CI role out of application logs and the audit trail.
  statement {
    sid     = "DenyAppAndAuditLogs"
    effect  = "Deny"
    actions = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = [
      "arn:aws:s3:::${local.p}-*-loki/*",
      "arn:aws:s3:::${local.audit_bucket}/*",
    ]
  }

  statement {
    sid       = "DenyAuditKey"
    effect    = "Deny"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.audit.arn]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "plan"
  role   = aws_iam_role.ci["plan"].id
  policy = data.aws_iam_policy_document.plan.json
}

# --- staging / prod deploy roles ----------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "env_read_only" {
  for_each   = local.envs
  role       = aws_iam_role.ci[each.key].name
  policy_arn = local.read_only_arn
}

data "aws_iam_policy_document" "env_deploy" {
  for_each = local.envs

  # Services whose resources can be scoped by name to this env
  statement {
    sid = "OwnNamedResources"
    actions = [
      "eks:*",
      "rds:*",
      "s3:*",
      "secretsmanager:*",
      "logs:*",
      "sns:*",
      "firehose:*",
      "cloudwatch:*",
    ]
    resources = local.env_named_arns[each.key]
  }

  # Services that can't be scoped by name (VPC, load balancers, keys, certificates).
  # kms:* includes this env's own state key. The Deny statements stop use of the other env's key and
  # of the bootstrap key (except for the audit bucket).
  statement {
    sid = "NetworkingAndKeys"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "kms:*",
      "acm:*",
    ]
    resources = ["*"]
  }

  # RDS-managed master passwords live in secrets named rds!...
  statement {
    sid = "RdsManagedSecrets"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:RotateSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UpdateSecret",
    ]
    resources = ["arn:aws:secretsmanager:${local.r}:${local.a}:secret:rds!*"]
  }

  # Roles this pipeline creates (EKS, nodes, Pod Identity) must carry the env's permissions boundary
  statement {
    sid = "IamWithBoundary"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = ["arn:aws:iam::${local.a}:role/${local.p}-${each.key}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arns[each.key]]
    }
  }

  statement {
    sid = "IamManageOwnRolesAndPolicies"
    actions = [
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = [
      "arn:aws:iam::${local.a}:role/${local.p}-${each.key}-*",
      "arn:aws:iam::${local.a}:policy/${local.p}-${each.key}-*",
    ]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "autoscaling.amazonaws.com",
        "rds.amazonaws.com",
      ]
    }
  }

  # Deploy records for the audit trail. Write-only; Object Lock keeps them for 365 days.
  statement {
    sid       = "WriteDeployRecords"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.audit_bucket}/deploys/${each.key}/*"]
  }

  # Stop destructive EC2 actions on anything that isn't ours (shared account)
  statement {
    sid    = "DenyDeletingOtherProjectsNetworking"
    effect = "Deny"
    actions = [
      "ec2:TerminateInstances",
      "ec2:StopInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:DeleteVpc",
      "ec2:DeleteSubnet",
      "ec2:DeleteNatGateway",
      "ec2:DeleteInternetGateway",
      "ec2:DeleteSecurityGroup",
      "ec2:ReleaseAddress",
      "elasticloadbalancing:DeleteLoadBalancer",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/project"
      values   = [local.p]
    }
  }

  statement {
    sid       = "DenyAppLogs"
    effect    = "Deny"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["arn:aws:s3:::${local.p}-*-loki/*"]
  }
}

# Three managed policies per env role, each kept under the 6,144-character IAM limit:
# what it may do (deploy), and two sets of Deny guardrails.
resource "aws_iam_policy" "env_deploy" {
  for_each = local.envs

  name        = "${local.p}-ci-${each.key}-deploy"
  description = "What the ${each.key} pipeline may change"
  policy      = data.aws_iam_policy_document.env_deploy[each.key].json
}

resource "aws_iam_policy" "protect_bootstrap" {
  name        = "${local.p}-ci-protect-bootstrap"
  description = "Deny changes to state, audit trail, CI roles, boundaries and ECR repos"
  policy      = data.aws_iam_policy_document.protect_bootstrap.json
}

resource "aws_iam_policy" "deny_other_env" {
  for_each = local.envs

  name        = "${local.p}-ci-${each.key}-deny-${each.value.other}"
  description = "Deny every action on ${each.value.other} resources"
  policy      = data.aws_iam_policy_document.deny_other_env[each.key].json
}

locals {
  env_role_policies = merge([for e in keys(local.envs) : {
    "${e}-deploy"     = { role = e, arn = aws_iam_policy.env_deploy[e].arn }
    "${e}-protect"    = { role = e, arn = aws_iam_policy.protect_bootstrap.arn }
    "${e}-deny-other" = { role = e, arn = aws_iam_policy.deny_other_env[e].arn }
  }]...)
}

resource "aws_iam_role_policy_attachment" "env_policies" {
  for_each   = local.env_role_policies
  role       = aws_iam_role.ci[each.value.role].name
  policy_arn = each.value.arn
}

# --- workload permissions boundaries ----------------------------------------------------------
# Every role the env pipeline creates (EKS cluster, nodes, Pod Identity roles) gets this boundary.
# The role's own policies grant access; the boundary caps the maximum.

data "aws_iam_policy_document" "workload_boundary_base" {
  statement {
    sid       = "AllowWithinGuardrails"
    actions   = ["*"]
    resources = ["*"]
  }

  # Workloads (nodes, pods) never need IAM. Anything they need, such as the ELB service-linked role,
  # is created by the pipeline role instead.
  statement {
    sid       = "DenyAllIam"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyStateBucket"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = flatten([for b in values(local.state_buckets) : ["arn:aws:s3:::${b.name}", "arn:aws:s3:::${b.name}/*"]])
  }

  statement {
    sid    = "DenyImagePush"
    effect = "Deny"
    actions = [
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [local.ecr_repo_arn]
  }
}

data "aws_iam_policy_document" "workload_boundary" {
  for_each = local.envs
  source_policy_documents = [
    data.aws_iam_policy_document.workload_boundary_base.json,
    data.aws_iam_policy_document.protect_bootstrap.json,
    data.aws_iam_policy_document.deny_other_env[each.key].json,
  ]
}

resource "aws_iam_policy" "workload_boundary" {
  for_each = local.envs

  name        = "${local.p}-${each.key}-workload-boundary"
  description = "Permissions boundary for every role created by the ${each.key} pipeline"
  policy      = data.aws_iam_policy_document.workload_boundary[each.key].json
}
