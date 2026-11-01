provider "aws" {
  region  = var.region
  profile = var.aws_profile

  # Refuse to run against any other account (the default CLI profile on this laptop is a work account)
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      project    = var.project
      env        = "shared"
      component  = "bootstrap"
      managed-by = "terraform"
      repo       = "${var.github_org}/${var.infra_repo}"
    }
  }
}
