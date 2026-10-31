# yq-merlion-infra

Infrastructure, deployment and operations for the **Merlion Trust Bank** capstone (Use Case A). It runs Google's Bank of Anthos on Amazon EKS in `ap-southeast-1`.

Application source lives in [yq-merlion-app](https://github.com/yq-merlion/yq-merlion-app).

## Hard constraints

1. **Data residency:** customer data, databases, backups and application logs stay in `ap-southeast-1`. No SaaS tool stores or processes customer data or logs.
2. **Auditability:** every production change is traceable (who, what, when, which pipeline). No direct console changes to production.
3. **Audit log retention:** pipeline and infrastructure audit logs are kept for at least 1 year and protected from tampering by the engineering team.

## Team

Solo project. One person covers all roles.

| Role | Owner |
|---|---|
| Solutions Architect | @yqyeoh |
| DevSecOps Engineer | @yqyeoh |
| Site Reliability Engineer | @yqyeoh |

## Repository layout

| Path | Contents |
|---|---|
| `infra/` | Terraform: bootstrap, reusable modules, staging and prod environments |
| `deploy/` | Kubernetes config for Bank of Anthos, synced by Argo CD |
| `observability/` | Prometheus, Loki and Grafana config, dashboards, alert rules |
| `docs/` | Architecture, constraint mapping, cost estimate, SLOs, ADRs, runbooks |
| `.github/` | Workflows, CODEOWNERS, PR template |

## Architecture

_To do: diagram and summary._

## Setup

_To do._

## Pipeline

_To do: feature branch → PR → staging → production, and how a failed security gate is handled._

## Operations

_To do: dashboards, alerts, SLOs, runbooks, teardown._
