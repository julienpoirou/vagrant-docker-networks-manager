# frozen_string_literal: true

require "vagrant-docker-networks-manager/network_builder"
require "vagrant-docker-networks-manager/config"

RSpec.describe VagrantDockerNetworksManager::NetworkBuilder do
  def build_config(overrides = {})
    cfg = VagrantDockerNetworksManager::Config.new
    cfg.finalize!
    overrides.each { |k, v| cfg.public_send("#{k}=", v) }
    cfg
  end

  it "construit la commande avec toutes les options bridge" do
    cfg = build_config(
      network_name: "net1",
      network_type: "bridge",
      network_subnet: "172.28.10.0/24",
      network_gateway: "172.28.10.1",
      ip_range: "172.28.10.0/25",
      enable_ipv6: true,
      network_attachable: true
    )

    args = described_class.new(cfg, machine_id: "MID123").build_create_command_args
    expect(args).to start_with("network", "create")
    expect(args).to include("--label", "com.vagrant.plugin=docker_networks_manager")
    expect(args).to include("--label", "com.vagrant.machine_id=MID123")
    expect(args).to include("--driver", "bridge")
    expect(args).to include("--subnet", "172.28.10.0/24")
    expect(args).to include("--gateway", "172.28.10.1")
    expect(args).to include("--ip-range", "172.28.10.0/25")
    expect(args).to include("--ipv6")
    expect(args).to include("--attachable")
    expect(args.last).to eq("net1")
  end

  it "ajoute --opt parent=... pour macvlan" do
    cfg = build_config(
      network_name: "macv",
      network_type: "macvlan",
      network_parent: "eth0",
      network_subnet: "192.168.50.0/24",
      network_gateway: "192.168.50.1"
    )
    args = described_class.new(cfg, machine_id: nil).build_create_command_args
    expect(args).to include("--driver", "macvlan")
    expect(args).to include("--opt", "parent=eth0")
  end
end
