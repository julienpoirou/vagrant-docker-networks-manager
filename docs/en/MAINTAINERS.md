# Maintainers guide

## Issue triage
- Labels: `type:bug`, `type:feature`, `question`
- Onboarding: `good first issue`, `help wanted`
- Ask for a minimal repro when needed

## PRs
- Keep them focused, update tests + docs
- Prefer squash merge
- Dependency PRs (Renovate/Dependabot) can be auto‑merged per policy

## Releases
- Do not tag manually: let **Release Please** handle it.
- Review the generated CHANGELOG in the Release PR.

## Security
- Follow `docs/SECURITY.md`.
