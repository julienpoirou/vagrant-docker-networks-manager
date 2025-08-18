# Contribuer

Merci de votre intérêt pour **vagrant-docker-networks-manager** 💙

## Pré‑requis
- Ruby 3.1+ (la CI teste 3.1 → 3.4)
- Bundler
- Docker (optionnel pour dev local)
- Vagrant (optionnel pour tests manuels)
- Node (optionnel si vous exécutez commitlint localement)

## Mise en route
```bash
git clone https://github.com/<you>/vagrant-docker-networks-manager
cd vagrant-docker-networks-manager
bundle install
bundle exec rake      # lance RSpec
bundle exec rubocop   # lint Ruby
```

## Branches & commits
- Branchez depuis `main`: `feat/x`, `fix/y`, etc.
- **Conventional Commits** obligatoires :
  - `feat(scope): ...` (minor)
  - `fix(scope): ...` (patch)
  - `feat!(scope): ...` ou `refactor!: ...` (major)
- La CI vérifie le format via **commitlint**.

## Tests
- Unitaires : `bundle exec rspec`
- Lint : `bundle exec rubocop`
- Build gem : `gem build vagrant-docker-networks-manager.gemspec`

## i18n
- Toute nouvelle chaîne → **en.yml** + **fr.yml**.
- Gardez la parité : mêmes clés, traductions claires.

## Ouvrir une PR
- Remplissez le template.
- Cochez la checklist : tests OK, lint OK, docs mises à jour.
- Pas besoin d’éditer `CHANGELOG.md` ni la version : **Release Please** s’en charge.

## Discussion
- Questions : issues ou discussions.
- Bonnes premières contributions : label **good first issue**.
