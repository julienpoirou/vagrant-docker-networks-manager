# CI/CD

## Workflows
- **Lint GitHub Actions** (`actionlint.yml`): actionlint + shellcheck on `.github/workflows/*`.
- **CI** (`ci.yml`): RSpec, RuboCop, gem build on Ruby 3.1 → 3.4.
- **Commitlint** (`commitlint.yml`): enforces Conventional Commits on PR.
- **Release** (`release-please.yml`): manages Release PR + CHANGELOG.
- **Publish** (`gem-publish.yml`): publishes to RubyGems + GitHub Packages + attaches `.gem` to Release.
- **Dependabot auto‑merge**: auto‑merge security patch/minor updates.

## Secrets
- `RUBYGEMS_API_KEY` (optional, required for RubyGems)
- `GITHUB_TOKEN` (provided by GitHub)

## Tips
- Protect `main` branch: required reviews + checks.
- Prefer squash merges for clean history.
