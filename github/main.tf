terraform {
  required_version = ">= 1.10"
  required_providers {
    github = { source = "integrations/github", version = "~> 6.4" }
  }
  backend "s3" {
    key          = "github/terraform.tfstate"
    use_lockfile = true
  }
}

provider "github" {
  owner = var.owner
  # token comes from GITHUB_TOKEN (the GH_TF_TOKEN secret in CI)
}

variable "owner" {
  type    = string
  default = "sergeyyegournov"
}

variable "app_repo" {
  type    = string
  default = "ship-it-demo"
}

# --- the app repo and its merge policy -------------------------------------
resource "github_repository" "app" {
  name                   = var.app_repo
  description            = "End-to-end demo of Anthropic's AI-native SDLC playbook"
  visibility             = "public"
  is_template            = true
  has_issues             = true
  allow_squash_merge     = true
  allow_merge_commit     = false
  allow_rebase_merge     = false
  delete_branch_on_merge = true
  vulnerability_alerts   = true

  lifecycle { prevent_destroy = true }
}

resource "github_actions_repository_permissions" "app" {
  repository = github_repository.app.name
  enabled    = true
}

# default workflow token is read-only; Actions may not approve PRs
resource "github_workflow_repository_permissions" "app" {
  repository                       = github_repository.app.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

# --- branch protection: the human gate on main ------------------------------
resource "github_branch_protection" "main" {
  repository_id                   = github_repository.app.node_id
  pattern                         = "main"
  enforce_admins                  = true
  required_linear_history         = false
  require_conversation_resolution = true
  allows_force_pushes             = false
  allows_deletions                = false

  required_status_checks {
    strict   = true
    contexts = ["test", "agent-evals"]
  }

  required_pull_request_reviews {
    required_approving_review_count = 1
    require_code_owner_reviews      = true
    dismiss_stale_reviews           = true
  }
}

# --- production environment: the second human gate --------------------------
data "github_user" "me" {
  username = var.owner
}

resource "github_repository_environment" "production" {
  repository          = github_repository.app.name
  environment         = "production"
  prevent_self_review = false

  reviewers {
    users = [data.github_user.me.id]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "main_only" {
  repository     = github_repository.app.name
  environment    = github_repository_environment.production.environment
  branch_pattern = "main"
}

# --- this repo (the infra repo) ------------------------------------------------
# Plans are required checks; there is a single maintainer, so no approval count. The human
# gate for infrastructure is the `production-infra` environment, which holds `apply`.
resource "github_repository" "infra" {
  name                   = "ship-it-demo-infra"
  description            = "Terraform for the ship-it-demo GitHub controls and AWS deployment"
  visibility             = "public"
  has_issues             = true
  allow_squash_merge     = true
  allow_merge_commit     = false
  allow_rebase_merge     = false
  delete_branch_on_merge = true

  lifecycle { prevent_destroy = true }
}

resource "github_branch_protection" "infra_main" {
  repository_id       = github_repository.infra.node_id
  pattern             = "main"
  enforce_admins      = false
  allows_force_pushes = false
  allows_deletions    = false

  required_status_checks {
    strict   = true
    contexts = ["plan (github)", "plan (aws)"]
  }
}

resource "github_repository_environment" "production_infra" {
  repository          = github_repository.infra.name
  environment         = "production-infra"
  prevent_self_review = false

  reviewers {
    users = [data.github_user.me.id]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "infra_main_only" {
  repository     = github_repository.infra.name
  environment    = github_repository_environment.production_infra.environment
  branch_pattern = "main"
}
