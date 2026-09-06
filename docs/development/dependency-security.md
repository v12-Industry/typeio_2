# Dependency & Security Scanning

This repo has two separate mechanisms for catching vulnerable
dependencies and leaked secrets — a native GitHub feature (Dependabot +
secret scanning) and a custom CI workflow (OSV-Scanner). They exist
side by side because the native feature has a real gap: Dependabot
doesn't support the one ecosystem this repo actually has dependencies
in. This page is the single place to read the whole picture; see
`docs/solution-proposals/security-scanning.md` for the full
investigation and decision behind it, and
[`ci.md`](ci.md#security-scan-workflow) for the OSV-Scanner workflow's
CI mechanics specifically (trigger shape, steps, how it differs from
the other workflows) — this page doesn't repeat that, it explains what
the two mechanisms are for and how to act on what they find.

## The two mechanisms, and why both exist

| | Dependabot (native) | OSV-Scanner (`security-scan.yml`) |
|---|---|---|
| What it is | A GitHub repo feature, not a CI workflow | A GitHub Actions workflow (Google's OSV-Scanner) |
| Ecosystems covered | npm only — GitHub has no Hackage/Cabal support (tracked upstream in `dependabot/dependabot-core#2745`, not shipped as of this writing) | Both: reads a scan-time-generated `cabal.project.freeze` for Haskell, and `package-lock.json` for npm |
| Config | `.github/dependabot.yml` | `.github/workflows/security-scan.yml` |
| Trigger | Continuous, run by GitHub itself | A weekly schedule only (`0 5 * * 1`), not per-PR — see below |
| Where findings show up | Security tab → Dependabot alerts; auto-opened PRs for fixes | The workflow run's job summary |
| Blocking? | No — alerts, not merge gates | No — `continue-on-error: true`, not a required check |

**Why both**: Dependabot alerts/security-updates/version-updates are
free on this public repo and need zero workflow code, but they only
understand ecosystems GitHub has built support for. npm is on that
list; Hackage/Cabal is not. Since this repo's real dependency surface
is Haskell (`typeio.cabal`), Dependabot alone would leave that surface
completely unscanned. OSV-Scanner is the gap-filler for exactly that —
one CI job, both ecosystems, so npm ends up covered twice (redundant,
but harmless) and Haskell ends up covered at all.

There's currently no `package.json`/`package-lock.json` in the repo —
an orphaned `wifi-password` entry has since been removed — so the
npm side of both mechanisms has nothing to scan today. Both are
deliberately kept ready to go the moment real JS dependencies exist
again (see the `npm` entry in `.github/dependabot.yml`).

## Dependabot

`.github/dependabot.yml` has one `package-ecosystem: npm` entry
(`directory: /`, weekly `schedule`) and no Hackage entry — GitHub
doesn't support one yet. Three related repo-settings features are
enabled (configured directly in **Settings → Code security**, not in
this file, and free on a public repo with no billing enrollment):

- **Secret scanning** — flags credentials/tokens accidentally committed
  to the repo, independent of any ecosystem.
- **Dependabot alerts** — flags known-vulnerable dependencies (for
  ecosystems GitHub supports; npm here) against GitHub's advisory
  database.
- **Dependabot security updates** — auto-opens a PR bumping a flagged
  dependency to a fixed version.

None of this needs a workflow file to run — it's always on, driven by
GitHub itself.

## OSV-Scanner (`security-scan.yml`)

Fills the Hackage gap: on a weekly schedule, the workflow runs
`cabal freeze` to produce a `cabal.project.freeze` (not committed to
the repo — generated fresh each run, see the proposal's §5), then runs
[OSV-Scanner](https://github.com/google/osv-scanner) against it and
against `package-lock.json` if one exists. Results are appended to the
run's job summary — there's no separate dashboard. See
[`ci.md`'s "Security scan workflow"](ci.md#security-scan-workflow)
section for the exact steps and trigger reasoning.

It deliberately does not run on every PR into `main` to catch a newly
*introduced* vulnerable dependency at the point it landed. That half
is deliberately not a PR check: a per-PR run kept surfacing findings unrelated to
what the given PR actually changed, on an informational-only check
nothing could act on from inside that PR anyway. The weekly `schedule`
alone still covers what a PR trigger structurally can't — a dependency
that didn't change but became known-vulnerable since it was last
touched — so that's what's left.

It's deliberately **informational only** — `continue-on-error: true`,
not a required check — so a finding doesn't block whatever happens to
be in flight when the scheduled scan runs. See the proposal's §7 for
the full reasoning, including why this also avoids the "required check
silently stuck missing forever" trap `ci.md`'s [Why it always
runs](ci.md#why-it-always-runs-and-skips-internally-instead-of-using-paths)
section describes for `test.yml`.

## Where alerts and findings show up

- **Dependabot alerts and secret-scanning alerts**: repo's **Security**
  tab. A Dependabot security-update PR (when one is auto-opened) shows
  up as a normal PR from the `dependabot[bot]` author.
- **OSV-Scanner findings**: the **job summary** of the relevant
  `security-scan.yml` run, found in the workflow's own run history —
  it's schedule-only, so there's no PR to attach it to. There's
  no other surface for these; don't expect a Security-tab entry, since
  this workflow deliberately doesn't upload SARIF to Code Scanning (see
  `ci.md`'s explanation of why it uses the raw scanner action instead of
  this project's reusable workflow).

## Handling what comes up

- **A Dependabot security-update PR** (npm, auto-opened): review and
  merge it like any other PR — apply `type:chore` and `area:ci-cd`
  (or `area:frontend` if it's ever a real runtime JS dependency rather
  than tooling) per [`labels.md`](labels.md). These currently pass
  through `test.yml`'s required check same as any PR.
- **A Dependabot alert with no auto-fix PR available**, or a
  **secret-scanning alert**: triage manually — there's no automated
  path for these. File or update a `type:bug`/`type:chore` issue
  (matching area label) if a real fix is needed; a secret-scanning hit
  in particular should be treated as the credential being compromised
  (rotate it), not just removed from the diff.
- **An OSV-Scanner finding in a job summary**: since it's informational,
  nothing blocks automatically. Read the finding, decide whether it's
  real and actionable (a genuinely vulnerable resolved version) versus
  noise (e.g. a bound that theoretically allows a bad version but never
  resolves to one). If action is needed, it's usually bumping a version
  bound in `typeio.cabal` — track it as a normal `type:bug` or
  `type:chore` issue (`area:backend` for a Haskell dependency,
  `area:ci-cd` if it's about the scanning setup itself) rather than
  expecting the workflow to fix anything itself. There's currently no
  `.osv-scanner.toml` ignore-list for accepted-risk findings — see the
  proposal's §10 — so a finding that's judged not worth fixing has no
  suppression mechanism yet beyond noting it in the issue/PR.

## What this page deliberately doesn't cover

- The CI mechanics of `security-scan.yml` itself (steps, caching,
  trigger conditions) — that's [`ci.md`'s "Security scan
  workflow"](ci.md#security-scan-workflow) section.
- The full investigation behind why Dependabot+OSV-Scanner was chosen
  over alternatives, and the open questions left deliberately unresolved
  (exact cron time, an `.osv-scanner.toml` ignore list, revisiting
  OSV-Scanner's Haskell coverage if GitHub ever ships native Hackage
  support) — `docs/solution-proposals/security-scanning.md` §10.
- Infrastructure-dependency scanning (Terraform/Terragrunt providers and
  modules) — a separate surface, not designed yet; see the proposal's
  §8.
