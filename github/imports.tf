# The app repo was first configured by scripts/setup-github.sh. These blocks adopt that
# state so `terraform plan` shows no drift. After the first apply, Terraform is the
# source of truth and setup-github.sh is retired.
import {
  to = github_repository.app
  id = "ship-it-demo"
}
import {
  to = github_branch_protection.main
  id = "ship-it-demo:main"
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
  id = "ship-it-demo:production:main"
}

# The infra repo's own controls are created by scripts/setup-infra-repo.sh on first push,
# then adopted here.
import {
  to = github_repository.infra
  id = "ship-it-demo-infra"
}
import {
  to = github_branch_protection.infra_main
  id = "ship-it-demo-infra:main"
}
import {
  to = github_repository_environment.production_infra
  id = "ship-it-demo-infra:production-infra"
}
import {
  to = github_repository_environment_deployment_policy.infra_main_only
  id = "ship-it-demo-infra:production-infra:main"
}
