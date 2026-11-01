locals {
  account_id = var.account_id
  region     = var.region

  # One state bucket per layer (state.tf). Env buckets are named <project>-<env>-... and tagged with
  # their env, so the deny_other_env policy in guardrails.tf blocks the other env's bucket by name and by tag.
  state_buckets = {
    bootstrap = { name = "${var.project}-bootstrap-tfstate-${var.account_id}", env_tag = "shared" }
    staging   = { name = "${var.project}-staging-tfstate-${var.account_id}", env_tag = "staging" }
    prod      = { name = "${var.project}-prod-tfstate-${var.account_id}", env_tag = "prod" }
  }
  audit_bucket = "${var.project}-audit-${var.account_id}"

  trail_name = "${var.project}-audit-trail"
  trail_arn  = "arn:aws:cloudtrail:${var.region}:${var.account_id}:trail/${local.trail_name}"

  oidc_host     = "token.actions.githubusercontent.com"
  read_only_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"

  # Internal env name => GitHub environment and the env it must never touch
  envs = {
    staging = { github_environment = "staging", other = "prod" }
    prod    = { github_environment = "production", other = "staging" }
  }
}
