# Processus de release

## Automatique (recommandé)
1. Merge d’une PR de fonctionnalité vers `main`.
2. **Release Please** ouvre/actualise une **Release PR** (version + CHANGELOG).
3. Vous révisez et mergez la Release PR.
4. GitHub crée le **tag** + la **Release**.
5. L’event `release.published` déclenche **Publish** :
   - build du `.gem`
   - push sur **RubyGems** (si `RUBYGEMS_API_KEY` est présent)
   - push sur **GitHub Packages**
   - upload du `.gem` en asset de la Release.

## Sémantique de version
- `feat:` → **minor**
- `fix:` → **patch**
- `type!:` ou note “BREAKING CHANGE” → **major**

## Publication RubyGems
- Configurez le secret `RUBYGEMS_API_KEY` (Settings ▸ Secrets ▸ Actions).
- MFA RubyGems recommandée + dans le gemspec :
  ```ruby
  s.metadata["rubygems_mfa_required"] = "true"
  ```

## Publication GitHub Packages
- Aucune conf supplémentaire (utilise `GITHUB_TOKEN`).
