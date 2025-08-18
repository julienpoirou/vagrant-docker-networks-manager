# vagrant-docker-networks-manager

[![CI](https://github.com/julienpoirou/vagrant-docker-networks-manager/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/julienpoirou/vagrant-docker-networks-manager/actions/workflows/ci.yml)
[![CodeQL](https://github.com/julienpoirou/vagrant-docker-networks-manager/actions/workflows/codeql.yml/badge.svg)](https://github.com/julienpoirou/vagrant-docker-networks-manager/actions/workflows/codeql.yml)
[![Release](https://img.shields.io/github/v/release/julienpoirou/vagrant-docker-networks-manager?include_prereleases&sort=semver)](https://github.com/julienpoirou/vagrant-docker-networks-manager/releases)
[![RubyGems](https://img.shields.io/gem/v/vagrant-docker-networks-manager.svg)](https://rubygems.org/gems/vagrant-docker-networks-manager)
[![License](https://img.shields.io/github/license/julienpoirou/vagrant-docker-networks-manager.svg)](LICENSE.md)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-%23FE5196.svg)](https://www.conventionalcommits.org)
[![Renovate](https://img.shields.io/badge/Renovate-enabled-brightgreen.svg)](https://renovatebot.com)

Vagrant plugin to **manage Docker networks** with labeled ownership, safe lifecycle hooks, JSON output, and conflict-aware validation.

- Creates a Docker network on `vagrant up` (with labels & marker)
- Cleans it on `vagrant destroy` **only if owned by this machine** (safe)
- `vagrant network` CLI: `init | destroy | info | reload | list | prune | rename`
- IPv4/CIDR validation, subnet conflict detection, optional macvlan
- i18n (English 🇬🇧 / Français 🇫🇷), emojis, and normalized JSON output

> Requirements: **Vagrant ≥ 2.2**, **Ruby ≥ 3.1**, **Docker (CLI + daemon) running**

---

## Table of contents

- [Why this plugin?](#why-this-plugin)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Vagrantfile configuration](#vagrantfile-configuration)
- [CLI usage](#cli-usage)
- [JSON output examples](#json-output-examples)
- [Ownership & safety](#ownership--safety)
- [Subnet validation & conflicts](#subnet-validation--conflicts)
- [Internationalization](#internationalization)
- [Environment variables](#environment-variables)
- [Permissions & OS notes](#permissions--os-notes)
- [Troubleshooting](#troubleshooting)
- [Contributing & Development](#contributing--development)
- [License](#license)

> 🇫🇷 **Français :** voir [README.fr.md](README.fr.md)

---

## Why this plugin?

Managing Docker networks across Vagrant projects is tedious:

- naming consistency, subnet overlaps, and safe cleanup are error-prone
- destroying a VM shouldn’t delete someone else’s shared network
- operators need deterministic CLI **and** machine-readable output

This plugin solves these by **labeling** networks, keeping a **marker** per machine, validating **CIDR** + detecting **overlaps**, and offering a clean **CLI** with **JSON** output.

---

## Installation

From RubyGems (once published):

```bash
vagrant plugin install vagrant-docker-networks-manager
```

From source (local path):

```bash
git clone https://github.com/julienpoirou/vagrant-docker-networks-manager
cd vagrant-docker-networks-manager
bundle install
rake
vagrant plugin install .    # install from the local gemspec
```

Check it’s available:

```bash
vagrant network version
vagrant network help
```

---

## Quick start

### Minimal Vagrantfile

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "hashicorp/ubuntu-22.04"

  # Docker network plugin config
  config.docker_network.network_name       = "myproj_net"        # ⚠️ personalize to avoid collisions
  config.docker_network.network_subnet     = "172.28.50.0/24"
  config.docker_network.network_gateway    = "172.28.50.1"
  config.docker_network.network_type       = "bridge"            # or "macvlan"
  config.docker_network.network_parent     = nil                 # required if macvlan
  config.docker_network.network_attachable = true
  config.docker_network.enable_ipv6        = false
  config.docker_network.ip_range           = nil                 # optional
  config.docker_network.cleanup_on_destroy = true
  config.docker_network.locale             = "en"                # "en" or "fr"
end
```

### Create the network on `up`

```bash
vagrant up
```

If a network with the same name already exists:
- if it’s **owned** by this machine (labels match), it’s “adopted”
- otherwise you simply get an info message (no destructive action)

### Destroy VM and clean the network

```bash
vagrant destroy
```

- The network is removed **only** if created/owned by this machine.
- To also remove attached containers during Vagrant destroy:

```bash
VDNM_DESTROY_WITH_CONTAINERS=1 vagrant destroy
```

---

## Vagrantfile configuration

All options (with defaults):

| Key                         | Type    | Default            | Notes |
|----------------------------|---------|--------------------|-------|
| `network_name`             | String  | `"network_lo1"`    | ⚠️ Personalize to avoid collisions across projects. |
| `network_subnet`           | String  | `"172.28.100.0/26"`| Must be **aligned** IPv4/CIDR (e.g. `x.y.z.0/nn`). |
| `network_type`             | String  | `"bridge"`         | `"bridge"` or `"macvlan"`. |
| `network_gateway`          | String  | `"172.28.100.1"`   | Must be a **host** address inside `network_subnet`. |
| `network_parent`           | String  | `nil`              | **Required** if `network_type == "macvlan"`. |
| `network_attachable`       | Bool    | `false`            | Adds `--attachable`. |
| `enable_ipv6`              | Bool    | `false`            | Adds `--ipv6`. |
| `ip_range`                 | String  | `nil`              | IPv4/CIDR **inside** `network_subnet`. |
| `cleanup_on_destroy`       | Bool    | `true`             | Remove network on `vagrant destroy` if owned/created. |
| `locale`                   | String  | `"en"`             | `"en"` or `"fr"`. |

Validation performed:
- Docker name constraints, aligned IPv4/CIDR, `gateway` not network/broadcast
- `ip_range` must be included in `network_subnet`
- `macvlan` requires `network_parent`

---

## CLI usage

```
vagrant network <command> [args] [options]

Commands:
  init    <name> <subnet>
  destroy <name> [--with-containers] [--yes]
  reload  <name> [--yes]
  info    <name>
  list    [--json]
  prune   [--yes]
  rename  <old> <new> [<subnet>] [--yes]
  version

Global options:
  --json            # machine-readable output
  --yes, -y         # auto-confirm prompts
  --quiet           # reduce output (hide info)
  --no-emoji        # disable emojis
  --lang en|fr      # force language
```

Examples:

```bash
vagrant network init mynet 172.28.100.0/26
vagrant network info mynet
vagrant network list
vagrant network destroy mynet --with-containers --yes
vagrant network reload mynet --yes
vagrant network rename oldnet newnet --yes
vagrant network rename oldnet same-name 10.10.0.0/24 --yes
vagrant network prune --yes
```

---

## JSON output examples

Enable with `--json` for any command.

**init**
```json
{"action":"init","status":"success","data":{"name":"mynet","subnet":"172.28.100.0/26"}}
```

**info**
```json
{
  "action":"info",
  "status":"success",
  "data":{
    "network":{
      "Name":"mynet",
      "Id":"...docker-id...",
      "Driver":"bridge",
      "Subnets":["172.28.100.0/26"],
      "Containers":[{"Name":"web","IPv4":"172.28.100.2/26"}]
    }
  }
}
```

**prune (nothing to do)**
```json
{"action":"prune","status":"success","data":{"pruned":0,"items":[]}}
```

Errors are normalized:
```json
{"action":"destroy","status":"error","error":"Network not found.","data":{"name":"ghost"}, "code":1}
```

---

## Ownership & safety

- Networks are created with labels:
  - `com.vagrant.plugin=docker_networks_manager`
  - `com.vagrant.machine_id=<VAGRANT_MACHINE_ID>`
- A **marker file** is also written in:  
  `.vagrant/machines/<name>/<provider>/docker-networks/<network>.json`

On `vagrant destroy`, the plugin **only removes** a network if:
- the marker indicates it was created by this machine, **or**
- labels match this machine’s id (ownership)

If a network exists but is not owned, the plugin leaves it untouched.

---

## Subnet validation & conflicts

Before creating (or renaming to a new subnet), the plugin:

1. Validates `network_subnet` is an **aligned IPv4/CIDR**  
   (e.g. `172.28.100.0/24`, not `172.28.100.1/24`)
2. Scans existing Docker networks and checks for **overlaps**  
   (ignoring the target network when appropriate)

This prevents hard-to-debug IP conflicts.

---

## Internationalization

- Locales: **en**, **fr**
- Choose via CLI `--lang en|fr`, or set `locale` in your Vagrantfile, or `VDNM_LANG=en|fr`.

Emojis can be disabled with `--no-emoji`.

---

## Environment variables

| Variable                         | Purpose |
|----------------------------------|---------|
| `VDNM_LANG`                      | Force locale (`en`/`fr`) in hooks. |
| `VDNM_VERBOSE` | When `1`, prints the full `docker` command on STDERR and shows the native Docker output. |
| `VDNM_SKIP_CONFLICTS` | When `1`, the reload ignores subnet conflict detection (dangerous, for experts only). |
| `VDNM_DESTROY_WITH_CONTAINERS`   | When `1`, on Vagrant destroy the plugin also runs `docker rm -f` for attached containers (in addition to disconnect). |

> The CLI `vagrant network destroy <name> --with-containers` achieves the same for the **manual command**.

---

## Permissions & OS notes

- **Linux / macOS**: modifying `/etc/hosts` requires privileges. The plugin pipes through `sudo tee -a` when appending, and writes the file when removing. You may be prompted for your password.
- **Windows**: the plugin uses **PowerShell elevation** (`Start-Process -Verb RunAs`) when needed to append or rewrite the hosts file.

> If your shell is already elevated (root/Admin), no prompts appear.

---

## Troubleshooting

- **Docker is unavailable**: ensure Docker Desktop/daemon is running and the CLI works (`docker info`).
- **Invalid subnet**: use aligned IPv4/CIDR (e.g. `10.0.0.0/24`).
- **Subnet already in use**: another network overlaps. Pick a different range.
- **Remove failed**: some containers or other constraints may block `docker network rm`. Try `--verbose` (`VDNM_VERBOSE=1`) to see Docker’s output.
- **macvlan**: remember to set `network_parent` (host interface).

---

## Contributing & Development

```bash
git clone https://github.com/julienpoirou/vagrant-docker-networks-manager
cd vagrant-docker-networks-manager
bundle install
rake          # runs RSpec
```

- Conventional Commits enforced in PRs.
- CI runs RuboCop, tests, and builds the gem.
- See `docs/en/CONTRIBUTING.md` and `docs/en/DEVELOPMENT.md` if present.

---

## License

MIT © 2025 [Julien Poirou](mailto:julienpoirou@protonmail.com)

--- 

> Tip: prefer setting a **project-specific** `network_name` (e.g. `myapp_net`) to avoid collisions if multiple Vagrant projects run on the same host.
