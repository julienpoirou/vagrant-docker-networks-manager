# Développement

## Structure
- `lib/...` : code du plugin (actions, config, util, i18n)
- `spec/...` : RSpec (mocks Vagrant, tests de commandes)
- `locales/` : en/fr
- `README.md` : usage rapide

## Lancer les tests
```bash
bundle exec rake         # exécute RSpec
bundle exec rubocop      # lint
gem build vagrant-docker-networks-manager.gemspec
```

## Tester le plugin en local avec Vagrant
```bash
vagrant plugin install .
vagrant network version --json
# Dans un Vagrantfile, configurez config.docker_network.*
vagrant up
```

Astuce debug :
```bash
export VDNM_VERBOSE=1       # affiche les commandes docker
export VDNM_LANG=fr         # force la langue
```

## Ajouter une sous‑commande CLI
- Implémenter dans `lib/.../command.rb`
- Ajouter l'aide dans `locales/*/help.topic.<cmd>`
- Couvrir via RSpec (voir `spec/command_spec.rb`)

## i18n – bonnes pratiques
- Utilisez `UiHelpers.t!` pour signaler une clé manquante côté tests.
- Évitez les messages inline; centralisez dans les locales.
