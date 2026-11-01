variable "region" {
  description = "Single AWS region for every Merlion resource. See docs/adr/0002-deployment-region.md."
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS account Terraform is allowed to run against"
  type        = string
  default     = "255945442255"
}

variable "aws_profile" {
  description = "Local AWS CLI profile for the one-off bootstrap apply"
  type        = string
  default     = "personal"
}

variable "project" {
  description = "Prefix for resource names and the project tag"
  type        = string
  default     = "yq-merlion"
}

variable "github_org" {
  type    = string
  default = "yq-merlion"
}

variable "app_repo" {
  type    = string
  default = "yq-merlion-app"
}

variable "infra_repo" {
  type    = string
  default = "yq-merlion-infra"
}

variable "ecr_repositories" {
  description = "One ECR repo per image. accounts-db and ledger-db are only used to run the DB init Job against RDS (postgres base + upstream initdb scripts)."
  type        = list(string)
  default = [
    "frontend",
    "userservice",
    "contacts",
    "ledgerwriter",
    "balancereader",
    "transactionhistory",
    "loadgenerator",
    "accounts-db",
    "ledger-db",
  ]
}

variable "ecr_keep_images" {
  description = "Images kept per ECR repo; older ones expire"
  type        = number
  default     = 30
}

variable "audit_retention_days" {
  description = "Object Lock (governance) retention for the audit bucket"
  type        = number
  default     = 365
}
