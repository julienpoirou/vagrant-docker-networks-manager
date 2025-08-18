# Contributing

Thanks for your interest in **vagrant-docker-networks-manager** 💙

## Prerequisites
- Ruby 3.1+ (CI tests 3.1 → 3.4)
- Bundler
- Docker (optional for local dev)
- Vagrant (optional for manual tests)
- Node (optional if you run commitlint locally)

## Getting started
```bash
git clone https://github.com/<you>/vagrant-docker-networks-manager
cd vagrant-docker-networks-manager
bundle install
bundle exec rake      # run RSpec
bundle exec rubocop   # Ruby lint
```

## Branches & commits
- Branch off `main`: `feat/x`, `fix/y`, etc.
- **Conventional Commits** required:
  - `feat(scope): ...` (minor)
  - `fix(scope): ...` (patch)
  - `feat!(scope): ...` or `refactor!: ...` (major)
- CI enforces the format via **commitlint**.

## Tests
- Unit: `bundle exec rspec`
- Lint: `bundle exec rubocop`
- Build gem: `gem build vagrant-docker-networks-manager.gemspec`

## i18n
- Any new message → **en.yml** + **fr.yml**.
- Keep parity: same keys, proper translations.

## Open a PR
- Fill the PR template.
- Checklist: tests green, lint OK, docs updated.
- No need to edit `CHANGELOG.md` or the version: **Release Please** will do it.

## Discussion
- Questions: issues or discussions.
- First contributions welcome: **good first issue** label.
