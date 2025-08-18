# Development

## Layout
- `lib/...`: plugin code (actions, config, util, i18n)
- `spec/...`: RSpec (Vagrant mocks, command tests)
- `locales/`: en/fr
- `README.md`: quick usage

## Run tests
```bash
bundle exec rake         # runs RSpec
bundle exec rubocop      # lint
gem build vagrant-docker-networks-manager.gemspec
```

## Try the plugin locally with Vagrant
```bash
vagrant plugin install .
vagrant network version --json
# In a Vagrantfile, set config.docker_network.*
vagrant up
```

Debug tips:
```bash
export VDNM_VERBOSE=1     # print docker commands
export VDNM_LANG=en       # force language
```

## Add a CLI subcommand
- Implement in `lib/.../command.rb`
- Add help text under `locales/*/help.topic.<cmd>`
- Cover with RSpec (see `spec/command_spec.rb`)

## i18n best practices
- Use `UiHelpers.t!` to catch missing keys in tests.
- Avoid inline strings; centralize in locale files.
