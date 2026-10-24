#!/bin/bash
# One-time bootstrap of THIS repo's controls so the first Terraform run can adopt them.
# After github/ is applied, Terraform owns them and this script is not needed again.
set -eu
repo=${1:-sergeyyegournov/ship-it-demo-infra}
uid=$(gh api user --jq .id)
gh api -X PATCH "repos/$repo" -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false -F delete_branch_on_merge=true >/dev/null
gh api -X PUT "repos/$repo/environments/production-infra" --input - >/dev/null <<JSON
{"reviewers":[{"type":"User","id":$uid}],"prevent_self_review":false,"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
JSON
gh api -X POST "repos/$repo/environments/production-infra/deployment-branch-policies" -f name=main >/dev/null 2>&1 || true
echo "environment production-infra ready (reviewer: $(gh api user --jq .login))"
echo "! branch protection is added after the first plan run so the check names exist: see README"
