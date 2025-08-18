# Release process

## Automatic (recommended)
1. Merge a feature PR into `main`.
2. **Release Please** opens/updates a **Release PR** (version + CHANGELOG).
3. You review and merge the Release PR.
4. GitHub creates the **tag** + **Release**.
5. The `release.published` event triggers **Publish**:
   - build the `.gem`
   - push to **RubyGems** (if `RUBYGEMS_API_KEY` is configured)
   - push to **GitHub Packages**
   - upload the `.gem` as a Release asset.

## SemVer mapping
- `feat:` → **minor**
- `fix:` → **patch**
- `type!:` or a “BREAKING CHANGE” note → **major**

## RubyGems publishing
- Configure `RUBYGEMS_API_KEY` (Settings ▸ Secrets ▸ Actions).
- Enable MFA on RubyGems and in gemspec:
  ```ruby
  s.metadata["rubygems_mfa_required"] = "true"
  ```

## GitHub Packages publishing
- No extra config needed (uses `GITHUB_TOKEN`).
