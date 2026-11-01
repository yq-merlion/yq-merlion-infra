# The GitHub OIDC provider already exists in this shared account, and there can only be one
# per URL, so read it instead of creating it.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://${local.oidc_host}"

  lifecycle {
    postcondition {
      condition     = contains(self.client_id_list, "sts.amazonaws.com")
      error_message = "The existing GitHub OIDC provider doesn't list sts.amazonaws.com as an audience."
    }
  }
}

# Trust policy for a GitHub Actions role: only one exact `sub` claim may assume it
data "aws_iam_policy_document" "github_trust" {
  for_each = {
    ecr_push = "repo:${var.github_org}/${var.app_repo}:ref:refs/heads/main"
    plan     = "repo:${var.github_org}/${var.infra_repo}:pull_request"
    staging  = "repo:${var.github_org}/${var.infra_repo}:environment:${local.envs.staging.github_environment}"
    prod     = "repo:${var.github_org}/${var.infra_repo}:environment:${local.envs.prod.github_environment}"
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [each.value]
    }
  }
}
