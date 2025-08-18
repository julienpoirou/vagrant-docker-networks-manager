# vagrant-docker-networks-manager

[![CI](https://github.com/julienpoirou/vagrant-docker-networks-manager/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/julienpoirou/vagrant-docker-networks-manager/actions/workflows/ci.yml)
[![CodeQL](https://github.com/julienpoirou/vagrant-docker-networks-manager/actions/workflows/codeql.yml/badge.svg)](https://github.com/julienpoirou/vagrant-docker-networks-manager/actions/workflows/codeql.yml)
[![Release](https://img.shields.io/github/v/release/julienpoirou/vagrant-docker-networks-manager?include_prereleases&sort=semver)](https://github.com/julienpoirou/vagrant-docker-networks-manager/releases)
[![RubyGems](https://img.shields.io/gem/v/vagrant-docker-networks-manager.svg)](https://rubygems.org/gems/vagrant-docker-networks-manager)
[![License](https://img.shields.io/github/license/julienpoirou/vagrant-docker-networks-manager.svg)](LICENSE.md)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-%23FE5196.svg)](https://www.conventionalcommits.org)
[![Renovate](https://img.shields.io/badge/Renovate-enabled-brightgreen.svg)](https://renovatebot.com)

Plugin Vagrant pour **gérer les réseaux Docker** avec marquage d’appartenance (labels), hooks sûrs sur le cycle de vie, sortie JSON et détection des conflits de sous-réseaux.

- Crée un réseau Docker lors de `vagrant up` (avec labels & marqueur)
- Le supprime sur `vagrant destroy` **uniquement s’il appartient à cette machine** (sécurisé)
- CLI `vagrant network` : `init | destroy | info | reload | list | prune | rename`
- Validation IPv4/CIDR, détection de chevauchements, macvlan en option
- i18n (English 🇬🇧 / Français 🇫🇷), emojis, et sortie JSON normalisée

> Prérequis : **Vagrant ≥ 2.2**, **Ruby ≥ 3.1**, **Docker (CLI + daemon) actif**

---

## Sommaire

- [Pourquoi ce plugin ?](#pourquoi-ce-plugin-)
- [Installation](#installation)
- [Démarrage rapide](#démarrage-rapide)
- [Configuration Vagrantfile](#configuration-vagrantfile)
- [Utilisation CLI](#utilisation-cli)
- [Exemples de sortie JSON](#exemples-de-sortie-json)
- [Propriété & sécurité](#propriété--sécurité)
- [Validation du sous-réseau & conflits](#validation-du-sous-réseau--conflits)
- [Internationalisation](#internationalisation)
- [Variables d’environnement](#variables-denvironnement)
- [Permissions & remarques selon l’OS](#permissions--remarques-selon-los)
- [Dépannage](#dépannage)
- [Contribution & développement](#contribution--développement)
- [Licence](#licence)

> 🇬🇧 **English:** see [README.md](README.md)

---

## Pourquoi ce plugin ?

Gérer des réseaux Docker entre plusieurs projets Vagrant est fastidieux :

- cohérence des noms, chevauchements de sous-réseaux, nettoyage sûr…
- détruire une VM ne doit pas supprimer un réseau partagé par d’autres
- besoin d’une CLI déterministe **et** d’une sortie lisible par des outils

Ce plugin répond à ces points en **posant des labels**, en gardant un **marqueur** par machine, en validant les **CIDR** + détectant les **chevauchements**, et en fournissant une **CLI** propre avec sortie **JSON**.

---

## Installation

Depuis RubyGems (une fois publié) :

```bash
vagrant plugin install vagrant-docker-networks-manager
```

Depuis la source (chemin local) :

```bash
git clone https://github.com/julienpoirou/vagrant-docker-networks-manager
cd vagrant-docker-networks-manager
bundle install
rake
vagrant plugin install .    # installe depuis la gemspec locale
```

Vérifier :

```bash
vagrant network version
vagrant network help
```

---

## Démarrage rapide

### Vagrantfile minimal

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "hashicorp/ubuntu-22.04"

  # Configuration du plugin réseau Docker
  config.docker_network.network_name       = "myproj_net"        # ⚠️ personnalisez pour éviter les collisions
  config.docker_network.network_subnet     = "172.28.50.0/24"
  config.docker_network.network_gateway    = "172.28.50.1"
  config.docker_network.network_type       = "bridge"            # ou "macvlan"
  config.docker_network.network_parent     = nil                 # requis si macvlan
  config.docker_network.network_attachable = true
  config.docker_network.enable_ipv6        = false
  config.docker_network.ip_range           = nil                 # optionnel
  config.docker_network.cleanup_on_destroy = true
  config.docker_network.locale             = "en"                # "en" ou "fr"
end
```

### Créer le réseau à `up`

```bash
vagrant up
```

Si un réseau du même nom existe déjà :
- s’il est **possédé** par cette machine (labels identiques), il est « adopté »
- sinon, un simple message d’info est affiché (aucune action destructive)

### Détruire la VM et nettoyer le réseau

```bash
vagrant destroy
```

- Le réseau est supprimé **uniquement** s’il a été créé/possédé par cette machine.
- Pour supprimer aussi les conteneurs attachés pendant `destroy` :

```bash
VDNM_DESTROY_WITH_CONTAINERS=1 vagrant destroy
```

---

## Configuration Vagrantfile

Toutes les options (avec valeurs par défaut) :

| Clé                          | Type    | Défaut             | Notes |
|-----------------------------|---------|--------------------|-------|
| `network_name`              | String  | `"network_lo1"`    | ⚠️ Personnalisez pour éviter les collisions entre projets. |
| `network_subnet`            | String  | `"172.28.100.0/26"`| Doit être un **IPv4/CIDR aligné** (ex. `x.y.z.0/nn`). |
| `network_type`              | String  | `"bridge"`         | `"bridge"` ou `"macvlan"`. |
| `network_gateway`           | String  | `"172.28.100.1"`   | Doit être une **adresse hôte** dans `network_subnet`. |
| `network_parent`            | String  | `nil`              | **Requis** si `network_type == "macvlan"`. |
| `network_attachable`        | Bool    | `false`            | Ajoute `--attachable`. |
| `enable_ipv6`               | Bool    | `false`            | Ajoute `--ipv6`. |
| `ip_range`                  | String  | `nil`              | IPv4/CIDR **à l’intérieur** de `network_subnet`. |
| `cleanup_on_destroy`        | Bool    | `true`             | Supprime le réseau au `destroy` si possédé/créé par la machine. |
| `locale`                    | String  | `"en"`             | `"en"` ou `"fr"`. |

Validations effectuées :
- contraintes de nom Docker, IPv4/CIDR aligné, `gateway` ≠ réseau/broadcast  
- `ip_range` doit être inclus dans `network_subnet`  
- `macvlan` requiert `network_parent`

---

## Utilisation CLI

```
vagrant network <commande> [args] [options]

Commandes :
  init    <name> <subnet>
  destroy <name> [--with-containers] [--yes]
  reload  <name> [--yes]
  info    <name>
  list    [--json]
  prune   [--yes]
  rename  <old> <new> [<subnet>] [--yes]
  version

Options globales :
  --json            # sortie lisible par machine
  --yes, -y         # auto-confirmation
  --quiet           # moins de sortie (masque les infos)
  --no-emoji        # désactive les emojis
  --lang en|fr      # force la langue
```

Exemples :

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

## Exemples de sortie JSON

Activez `--json` sur n’importe quelle commande.

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

**prune (rien à faire)**
```json
{"action":"prune","status":"success","data":{"pruned":0,"items":[]}}
```

Erreurs normalisées :
```json
{"action":"destroy","status":"error","error":"Network not found.","data":{"name":"ghost"}, "code":1}
```

---

## Propriété & sécurité

- Les réseaux sont créés avec des labels :
  - `com.vagrant.plugin=docker_networks_manager`
  - `com.vagrant.machine_id=<VAGRANT_MACHINE_ID>`
- Un **fichier marqueur** est écrit ici :  
  `.vagrant/machines/<name>/<provider>/docker-networks/<network>.json`

Au `vagrant destroy`, le plugin **ne supprime** un réseau que si :
- le marqueur indique qu’il a été créé par cette machine, **ou**
- les labels correspondent à l’ID machine (propriété)

Si un réseau existe mais n’est pas possédé, le plugin ne touche à rien.

---

## Validation du sous-réseau & conflits

Avant création (ou renommage avec nouveau sous-réseau), le plugin :

1. Valide que `network_subnet` est un **IPv4/CIDR aligné**  
   (ex. `172.28.100.0/24`, pas `172.28.100.1/24`)
2. Scanne les réseaux Docker existants et cherche les **chevauchements**  
   (en ignorant le réseau cible quand pertinent)

Cela évite des conflits IP difficiles à diagnostiquer.

---

## Internationalisation

- Langues : **en**, **fr**
- Choix via `--lang en|fr`, ou en définissant `locale` dans le Vagrantfile, ou `VDNM_LANG=en|fr`.

Les emojis peuvent être désactivés avec `--no-emoji`.

---

## Variables d’environnement

| Variable                        | Rôle |
|---------------------------------|------|
| `VDNM_LANG`                     | Force la langue (`en`/`fr`) dans les hooks. |
| `VDNM_VERBOSE`                  | À `1`, affiche la commande `docker` complète sur STDERR et l’output natif. |
| `VDNM_SKIP_CONFLICTS`           | À `1`, ignore la détection de conflits de sous-réseaux lors de `reload` (dangereux, experts). |
| `VDNM_DESTROY_WITH_CONTAINERS`  | À `1`, pendant `vagrant destroy`, exécute aussi `docker rm -f` sur les conteneurs attachés (en plus de `disconnect`). |

> La CLI `vagrant network destroy <name> --with-containers` fait la même chose pour la **commande manuelle**.

---

## Permissions & remarques selon l’OS

- **Linux** : assurez-vous d’être dans le groupe `docker` (ou exécutez via `sudo`).  
- **macOS / Windows** : **Docker Desktop** doit être actif ; privilégiez un shell avec droits suffisants.
- Les opérations réseau (création/suppression) exigent des droits Docker standards, pas de modifications système externes.

---

## Dépannage

- **Docker indisponible** : assurez-vous que le daemon tourne et que la CLI fonctionne (`docker info`).

- **Sous-réseau invalide** : utilisez un IPv4/CIDR aligné (ex. `10.0.0.0/24`).

- **Sous-réseau déjà utilisé** : un autre réseau chevauche. Choisissez une plage différente.

- **Suppression impossible** : des conteneurs ou contraintes bloquent `docker network rm`. Essayez `--verbose` (`VDNM_VERBOSE=1`) pour voir la sortie Docker.

- **macvlan** : pensez à renseigner `network_parent` (interface hôte).

---

## Contribution & développement

```bash
git clone https://github.com/julienpoirou/vagrant-docker-networks-manager
cd vagrant-docker-networks-manager
bundle install
rake          # lance RSpec
```

- Conventional Commits appliqués en PR.
- La CI exécute RuboCop, les tests et construit la gem.
- Voir `docs/fr/CONTRIBUTING.md` et `docs/fr/DEVELOPMENT.md` si présents.

---

## Licence

MIT © 2025 [Julien Poirou](mailto:julienpoirou@protonmail.com)

---

> Astuce : définissez un `network_name` **spécifique au projet** (ex. `myapp_net`) pour éviter les collisions si plusieurs projets Vagrant tournent sur la même machine.
