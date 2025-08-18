# frozen_string_literal: true

require "vagrant-docker-networks-manager/action"
require "vagrant-docker-networks-manager/config"
require "pathname"
require "tmpdir"

RSpec.describe "Actions" do
  let(:ui) { instance_double("UI", info: nil, error: nil, warn: nil) }

  def machine_double(tmpdir, cfg)
    instance_double("Machine",
      id: "MID-1",
      data_dir: Pathname(tmpdir),
      config: double(docker_network: cfg)
    )
  end

  before do
    VagrantDockerNetworksManager::UiHelpers.setup_i18n!
    allow(VagrantDockerNetworksManager::Util).to receive(:docker_available?).and_return(true)
  end

  it "ActionUp crée le réseau et écrit le marqueur" do
    Dir.mktmpdir do |tmp|
      cfg = VagrantDockerNetworksManager::Config.new
      cfg.finalize!
      cfg.network_name = "testnet"
      cfg.network_subnet = "172.28.50.0/24"
      env = {
        machine: machine_double(tmp, cfg),
        ui: ui
      }

      allow(VagrantDockerNetworksManager::Util).to receive(:docker_network_exists?).with("testnet").and_return(false)
      allow(VagrantDockerNetworksManager::Util).to receive(:sh!).and_return(true)

      app = ->(_env) { true }
      described_class = VagrantDockerNetworksManager::ActionUp
      described_class.new(app, nil).call(env)

      marker = Pathname(tmp).join("docker-networks/testnet.json")
      expect(marker).to exist
    end
  end

  it "ActionDestroy supprime le réseau et le marqueur quand créé/possédé" do
    Dir.mktmpdir do |tmp|
      cfg = VagrantDockerNetworksManager::Config.new
      cfg.finalize!
      cfg.network_name = "gone"
      env = { machine: machine_double(tmp, cfg), ui: ui }

      dir = Pathname(tmp).join("docker-networks")
      FileUtils.mkdir_p(dir)
      File.write(dir.join("gone.json"), JSON.pretty_generate({name: "gone", machine_id: "MID-1"}))

      allow(VagrantDockerNetworksManager::Util).to receive(:docker_network_exists?).with("gone").and_return(true)
      allow(VagrantDockerNetworksManager::Util).to receive(:read_network_labels).with("gone")
        .and_return({"com.vagrant.plugin" => "docker_networks_manager", "com.vagrant.machine_id" => "MID-1"})
      allow(VagrantDockerNetworksManager::Util).to receive(:sh!).with("network", "rm", "gone").and_return(true)

      app = ->(_env) { true }
      VagrantDockerNetworksManager::ActionDestroy.new(app, nil).call(env)

      expect(dir.join("gone.json")).not_to exist
    end
  end
end
