# ship-it-demo-infra

Terraform for [`ship-it-demo`](https://github.com/sergeyyegournov/ship-it-demo), the end-to-end demo of Anthropic's AI-native SDLC playbook. Two roots:

| Root | Manages |
|---|---|
| `github/` | The app repo's merge policy, branch protection (`test`, `agent-evals`, 1 code-owner approval, admins included), the `production` environment and its required reviewer, workflow-token permissions. Also this repo's own controls. |
| `aws/` | ECR, ECS Fargate service, ALB, S3 + CloudFront (SPA at `/`, API at `/api/*`). Writes the resource names back to the app repo as Actions variables (`ECS_CLUSTER`, `WEB_BUCKET`, ...) so `deploy.yml` needs no lookups. |

Why the playbook cares: governance is code. Branch protection and the deployment approver live in reviewed, diffable files instead of console clicks, and changing them is itself a PR.

## How changes flow
- **PR:** `terraform.yml` runs fmt, validate and `plan` for both roots. The plans are required checks. The plan appears in the run summary.
- **Merge to `main`:** `apply` runs per root (aws first), held by the `production-infra` environment. A human approves each apply.
- **Teardown:** run the workflow manually with `destroy_aws`. It is also held by the environment.

State is in S3 (`ship-it-demo-tfstate-<account>`, created idempotently by `scripts/bootstrap-state.sh`, native S3 locking, no DynamoDB).

## One-time setup
1. Repo secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, and `GH_TF_TOKEN` (a fine-grained PAT for `ship-it-demo` and `ship-it-demo-infra`: Administration, Environments, Secrets, Variables write; Contents, Metadata read). The default `GITHUB_TOKEN` cannot manage another repo's protection or environments.
2. `scripts/setup-infra-repo.sh` creates the `production-infra` environment.
3. Open a PR, let both plans run once, then merge. The `github/imports.tf` blocks adopt the existing repo settings, so the first plan shows imports and no destructive changes.

## Notes and known limits
- Static IAM keys are used for now. Switching to GitHub OIDC is a small change in `aws/` plus a role.
- CloudFront talks to the ALB over HTTP. Viewers get TLS from CloudFront. A real service would add an ACM certificate on the ALB.
- Fargate tasks run in the default VPC's public subnets, with no NAT gateway, to keep cost near $25-35/month.
- The API keeps boards in memory. A redeploy resets them; this is a demo, not a datastore.
