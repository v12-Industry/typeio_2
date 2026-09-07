# Infrastructure

Repo-level configuration that would otherwise be set by hand via the GitHub
API/UI (branch protection on `main`, currently) is managed as code under
`infrastructure/`, using [OpenTofu](https://opentofu.org/) + Terragrunt.
This is the first piece of what may grow into environment-based cloud
infrastructure later — no cloud provider is chosen yet, so today this
covers GitHub repo config only.

**OpenTofu, not Terraform.** Same HCL, same workflow, same
`integrations/github` provider (it resolves the same on OpenTofu's
registry) — but the CLI binary is `tofu`, not `terraform`, and
`infrastructure/live/github/typeio_2/terragrunt.hcl` sets
`terraform_binary = "tofu"` so Terragrunt invokes it. Install it with
`brew install opentofu`. **Terragrunt must be `>= 1.1`** to work with
OpenTofu at all — `0.43.2` fails `terragrunt init` outright with
`Unable to parse Terraform version output: OpenTofu v1.12.6`, because it
only knows how to parse `terraform version`'s output format. `brew
upgrade terragrunt` if you hit that.

## Layout

- `infrastructure/modules/` — reusable modules. Nothing here is
  hardcoded to one repo/environment; modules take everything
  repo/environment-specific as an input variable.
  - `github-repo/` — wraps `github_branch_protection`, parameterized by
    repository, branch pattern, required status checks, required
    approving review count, `enforce_admins`, and force-push/deletion
    policy.
- `infrastructure/live/` — Terragrunt configs: the actual
  environment/target-specific values plugged into a module. Grouped by
  concern (`live/github/...`) rather than a flat list, so a future
  target (e.g. a cloud provider's environments) can be added alongside
  without reshuffling what's already here.
  - `live/github/typeio_2/terragrunt.hcl` — instantiates
    `modules/github-repo` with this repo's actual live values, and owns
    its own provider config (via a `generate` block) and remote state
    config (via a `remote_state` block) directly. There's deliberately
    no shared root `terragrunt.hcl` yet — with only one live GitHub
    config, an `include`-based parent config that exists purely to be
    shared has nothing to share. Reintroduce one (root
    `live/github/terragrunt.hcl` + `include "root"` in each child) once
    a second config under `live/github/` actually needs the same
    provider/backend wiring.

## State backend: Google Cloud Storage

GitHub has no equivalent to GitLab's built-in managed Terraform state
(GitLab implements the Terraform HTTP backend protocol directly in a
project; there's no GitHub-native counterpart), and a local state file
checked into git is not an option — it'd have to hold live GitHub
resource IDs, could diverge from reality with no locking, and there is
no CI runner set up yet to be the sole `apply`r of a local file safely.

A GCS bucket was chosen over a dedicated remote-state SaaS (HCP
Terraform, Spacelift, etc.) because GCP is the project's likely eventual
cloud target anyway — state storage there isn't a separate throwaway
account, it's a small first piece of the real thing. Terragrunt's `gcs`
`remote_state` block **creates the bucket itself** (versioned) on the
first `terragrunt init` if it doesn't already exist, so there's no
separate manual bootstrap step the way a SaaS backend needs a
workspace created by hand first.

(An earlier version of this used HCP Terraform's free tier instead —
also verified working, including that OpenTofu's `cloud` block does
genuinely talk to it, confirmed by running `tofu init` against
`hostname = "app.terraform.io"` and getting a real `tofu login` prompt
rather than a rejection. Switched to GCS on review once GCP
was confirmed as the likely target — no cloud-agnostic backend is worth
preferring over the real one once that's settled.)

**Not usable yet — merged ahead of the account existing.** This is
deliberate: the code is correct and ready, but running it before the GCP
side exists would just fail. One-time setup, whenever it happens:

1. Create (or reuse) a GCP project for this. `terragrunt init` from
   `infrastructure/live/github/typeio_2` will error until then — a
   confirmed-clean failure (`storage.NewClient() failed: ... could not
   find default credentials`), not a config bug.
2. Create a service account with permission to create/manage GCS
   buckets and objects in that project (e.g. `roles/storage.admin`, or
   narrower if preferred), and a JSON key for it.
3. `export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json` and
   `export GCS_STATE_PROJECT=<the GCP project ID>` — both env vars, per
   the existing "never hardcode credentials" convention; neither goes in
   any `.tf`/`.hcl` file.
4. `terragrunt init` from `infrastructure/live/github/typeio_2` —
   creates `typeio-2-opentofu-state` (versioned) if it doesn't exist yet.
   **Bucket names are globally unique across all of GCS**, like S3 — if
   that name is taken, change `bucket` in the `terragrunt.hcl` before
   running init, rather than fighting over a name someone else already
   owns.

## GitHub provider authentication

The `integrations/github` provider reads `GITHUB_TOKEN` from the
environment natively — it is never set in any `.tf`/`.hcl` file. Export
it (a PAT or GitHub App token with admin rights on the target repo)
before running any `terragrunt` command:

```sh
export GITHUB_TOKEN=<token with repo admin scope>
```

## Importing the existing branch protection

`infrastructure/live/github/typeio_2` was written to match what's
actually live on `main` today (required PR, 0 required approvals,
required status check `test`, strict, `enforce_admins`, no force
pushes, no deletions) — applying without importing first would try to
create a branch protection rule that already exists. Import it into the
GCS-backed state once, after the account setup above:

```sh
cd infrastructure/live/github/typeio_2
terragrunt import github_branch_protection.this typeio_2:main
terragrunt plan   # must show "No changes."
```

`repository_id` in the module is resolved via a `github_repository`
data source lookup (not passed as the repo name directly) — the
provider normalizes it to the repo's GraphQL node ID on read, so
passing the name would show a spurious destroy/recreate on every plan
after import.

This exact sequence (import + zero-diff plan, plus the `repository_id`
fix above) was verified against the real, live `main` branch protection
during development, using a temporary local-backend override that was
never committed. The same is expected to hold against GCS once the
account exists, since the backend does not affect the resource
configuration.

**Not yet covered by this module**: `main`'s merge-queue ruleset (see
[`ci.md`](ci.md#merge-queue)) was configured directly via the API, the
same hand-first-then-import path branch protection takes. The `github-repo` module only wraps
`github_branch_protection` today, not `github_repository_ruleset` —
whoever does the first real `terragrunt apply` should add a
`github_repository_ruleset` resource for it (and import the live
ruleset the same way) rather than assume branch protection is the only
drift to reconcile.

## Day to day

```sh
cd infrastructure/live/github/typeio_2
terragrunt plan
terragrunt apply
```
