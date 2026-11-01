output "region" {
  value = local.region
}

output "state_buckets" {
  description = "Backend bucket for each layer"
  value       = { for k, b in aws_s3_bucket.state : k => b.id }
}

output "state_kms_key_aliases" {
  description = "kms_key_id to put in each layer's backend block"
  value = merge(
    { bootstrap = aws_kms_alias.bootstrap.name },
    { for k, a in aws_kms_alias.state : k => a.name },
  )
}

output "audit_bucket" {
  value = aws_s3_bucket.audit.id
}

output "bootstrap_kms_key_arn" {
  value = aws_kms_key.bootstrap.arn
}

output "audit_kms_key_arn" {
  value = aws_kms_key.audit.arn
}

output "cloudtrail_arn" {
  value = aws_cloudtrail.audit.arn
}

output "ci_role_arns" {
  description = "Set these as AWS_ROLE_ARN in the GitHub workflows"
  value       = { for k, r in aws_iam_role.ci : k => r.arn }
}

output "workload_boundary_arns" {
  description = "Permissions boundary each env must attach to every IAM role it creates"
  value       = { for k, p in aws_iam_policy.workload_boundary : k => p.arn }
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}
