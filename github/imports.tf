# The app repo was first configured by scripts/setup-github.sh. These blocks adopt that
# state so `terraform plan` shows no drift. After the first apply, Terraform is the
# source of truth and setup-github.sh is retired.
import {
  to = github_repository.app
  id = "ship-it-demo"
}
# The app repo's rule is deleted and recreated whenever a workflow change needs a protection lift
# (scripts/setup-github.sh), which changes its ID. Re-adopt the live rule under a new address and
# forget the stale one without touching GitHub.
import {
  to = github_branch_protection.app_main
  id = "ship-it-demo:main"
}
removed {
  from = github_branch_protection.main
  lifecycle { destroy = false }
}
import {
  to = github_repository_environment.production
  id = "ship-it-demo:production"
}
import {
  to = github_actions_repository_permissions.app
  id = "ship-it-demo"
}
import {
  to = github_workflow_repository_permissions.app
  id = "ship-it-demo"
}
import {
  to = github_repository_environment_deployment_policy.main_only
  id = "ship-it-demo:production:64194582"
}

# The infra repo and its environment were created by scripts/setup-infra-repo.sh and are adopted
# here (policy ids are numeric). Its branch protection is created by Terraform.
import {
  to = github_repository.infra
  id = "ship-it-demo-infra"
}
import {
  to = github_repository_environment.production_infra
  id = "ship-it-demo-infra:production-infra"
}
import {
  to = github_repository_environment_deployment_policy.infra_main_only
  id = "ship-it-demo-infra:production-infra:64237680"
}
