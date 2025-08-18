# frozen_string_literal: true

require "vagrant"
require "i18n"

require_relative "version"
require_relative "helpers"
require_relative "command"
require_relative "config"
require_relative "network_builder"
require_relative "action"

module VagrantDockerNetworksManager
  class Plugin < Vagrant.plugin("2")
    name "docker_networks_manager"

    config(:docker_network) do
      VagrantDockerNetworksManager::Config
    end

    command "network" do
      VagrantDockerNetworksManager::Command
    end

    action_hook(:create_docker_network,  :machine_action_up) do |hook|
      hook.prepend(ActionUp)
    end

    action_hook(:cleanup_docker_network, :machine_action_destroy) do |hook|
      hook.append(ActionDestroy)
    end
  end
end
