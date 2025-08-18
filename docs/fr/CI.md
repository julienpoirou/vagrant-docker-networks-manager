# CI/CD

## Workflows
- **Lint GitHub Actions** (`actionlint.yml`) : actionlint + shellcheck sur `.github/workflows/*`.
- **CI** (`ci.yml`) : RSpec, RuboCop, build gem sur Ruby 3.1 → 3.4.
- **Commitlint** (`commitlint.yml`) : vérifie Conventional Commits sur la PR.
- **Release** (`release-please.yml`) : gère la Release PR et le CHANGELOG.
- **Publish** (`gem-publish.yml`) : publie sur RubyGems + GitHub Packages + attache le `.gem` à la Release.
- **Dependabot auto‑merge** : auto-merge des MAJ sécurité patch/minor.

## Secrets
- `RUBYGEMS_API_KEY` (optionnel, requis pour RubyGems)
- `GITHUB_TOKEN` (fourni par GitHub)

## Bonnes pratiques
- Protection de branche `main` : reviews + checks requis.
- Squash merge pour garder un historique propre.
