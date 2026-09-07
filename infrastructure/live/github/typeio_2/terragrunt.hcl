# OpenTofu, not Terraform -- see docs/development/infrastructure.md.
terraform_binary = "tofu"

terraform {
  source = "../../../modules/github-repo"
}

# GitHub provider authentication is via the GITHUB_TOKEN environment
# variable, which the provider reads natively -- never hardcode it here.
# See docs/development/infrastructure.md.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "github" {
  owner = "v12-Industry"
}
EOF
}

# Where OpenTofu state for this config lives: a GCS bucket, not local
# state and not checked into git -- see docs/development/infrastructure.md
# for why (GCP is the likely eventual cloud target) and for one-time
# account setup. Terragrunt creates the bucket itself (versioned) on the
# first `terragrunt init` if it doesn't already exist -- no separate
# bootstrap step. Not usable until GOOGLE_APPLICATION_CREDENTIALS and
# GCS_STATE_PROJECT are set up; merged ahead of that setup deliberately.
remote_state {
  backend = "gcs"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    project  = get_env("GCS_STATE_PROJECT", "")
    location = "US"
    bucket   = "typeio-2-opentofu-state"
    prefix   = "github/typeio_2"

    gcs_bucket_labels = {
      purpose = "opentofu-state"
    }
  }
}

inputs = {
  repository = "typeio_2"
  branch     = "main"

  # Both CI checks that gate a merge into main -- see
  # docs/development/ci.md. This covers only the *classic branch
  # protection* contexts list; the "main merge queue" ruleset carries
  # its own, separate required_status_checks rule naming the same two
  # checks, and this module doesn't manage rulesets, so that list is
  # maintained by hand. Changing what's required means changing both.
  required_status_check_contexts  = ["test", "integration-test"]
  required_status_check_strict    = true
  required_approving_review_count = 0
  dismiss_stale_reviews           = false
  require_code_owner_reviews      = false
  enforce_admins                  = true
  allow_force_pushes              = false
  allow_deletions                 = false
}
