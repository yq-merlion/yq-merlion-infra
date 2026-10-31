# deploy

Kubernetes configuration for Bank of Anthos, synced to each cluster by Argo CD.

- Helm chart for the Bank of Anthos services, plus the database init Job
- `envs/staging/` and `envs/prod/` values, including the image digests to deploy

Image digests are updated by pull requests opened from `yq-merlion-app`. Nobody edits the cluster directly.
