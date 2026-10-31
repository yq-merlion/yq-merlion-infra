# infra

Terraform for all AWS resources, in `ap-southeast-1`.

| Folder | Applied by | Contents |
|---|---|---|
| `bootstrap/` | A human admin, once, from a laptop | Terraform state bucket, GitHub OIDC roles, ECR, CloudTrail, Object Lock audit bucket |
| `modules/` | (reused by envs) | VPC, EKS, RDS, and other building blocks |
| `envs/staging/` | Pipeline, `merlion-ci-staging` role | Staging environment |
| `envs/prod/` | Pipeline, `merlion-ci-prod` role, after approval | Production environment |

Each environment has its own state file. The staging role can't read or write prod state.
