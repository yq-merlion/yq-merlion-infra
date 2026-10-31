# ADR-0001: Separate application and infrastructure repositories

## Status
Accepted. 2026-10-31

## Context
The brief asks for a defined repository and branching strategy with branch protection. Merlion's auditability constraint requires every production change to be traceable to who changed what, when, and through which approved pipeline.

## Options considered
1. One repository for app, infrastructure and deployment config (monorepo)
2. Two repositories: `yq-merlion-app` (source, image build) and `yq-merlion-infra` (Terraform, deployment config, observability, docs)

## Decision
Two repositories in the `yq-merlion` GitHub organisation, both public and both using GitHub Flow (`main` plus short-lived feature branches, merged by pull request).

- `yq-merlion-app` builds, scans and pushes images to ECR. It then opens a pull request in `yq-merlion-infra` to bump the image digests.
- `yq-merlion-infra` holds everything that changes the environments. Argo CD syncs the cluster from it.

## Consequences
- Good: tighter least privilege. The app pipeline's AWS role can only push to ECR, so it can't deploy anything.
- Good: every environment change, including a new image, is a reviewed pull request in one repository, which gives a clean audit trail.
- Trade-off: a release spans two pull requests (app change, then image bump). Deploy records store both commit SHAs to keep them linked.
- Trade-off: the app pipeline needs a GitHub credential to open pull requests in the infra repo. We use a GitHub App with short-lived tokens, limited to that repository.
- Repos are public: there are no secrets in code and only synthetic data.
- Revisit if we adopt a separate GitOps config repository or more teams join.
