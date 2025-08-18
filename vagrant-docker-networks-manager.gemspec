# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = "vagrant-docker-networks-manager"
  s.version     = File.read(File.join(__dir__, "lib/vagrant-docker-networks-manager/VERSION")).strip
  s.summary     = "Vagrant plugin to manage Docker networks with labels, JSON output, and cleanup on destroy"
  s.description = <<~DESC.strip
    Adds `vagrant network` subcommand, creates labeled Docker networks on `vagrant up`,
    and cleans them on `vagrant destroy` if created by this machine.
  DESC
  s.authors     = ["Julien Poirou"]
  s.email       = ["julienpoirou@protonmail.com"]
  s.homepage    = "https://github.com/julienpoirou/vagrant-docker-networks-manager"
  s.license     = "MIT"

  s.required_ruby_version = ">= 3.1"

  s.files = Dir[
    "lib/**/*",
    "locales/*.yml",
    "README.md",
    "LICENSE.md",
    "CHANGELOG.md"
  ]
  s.require_paths = ["lib"]

  s.add_dependency "i18n", ">= 1.8"

  s.add_development_dependency "rspec", "~> 3.12"
  s.add_development_dependency "rake", "~> 13.0"

  s.metadata = {
    "rubygems_mfa_required" => "true",
    "bug_tracker_uri" => 'https://github.com/julienpoirou/vagrant-docker-networks-manager/issues',
    "changelog_uri" => "https://github.com/julienpoirou/vagrant-docker-networks-manager/blob/main/CHANGELOG.md",
    "source_code_uri" => "https://github.com/julienpoirou/vagrant-docker-networks-manager",
    "homepage_uri" => "https://github.com/julienpoirou/vagrant-docker-networks-manager"
  }
end
