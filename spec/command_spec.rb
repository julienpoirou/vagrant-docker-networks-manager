# frozen_string_literal: true

require "ostruct"
require "json"

require "vagrant-docker-networks-manager/command"
require "vagrant-docker-networks-manager/util"
require "vagrant-docker-networks-manager/helpers"
require "vagrant-docker-networks-manager/version"

RSpec.describe VagrantDockerNetworksManager::Command do
  let(:env) { OpenStruct.new(ui: OpenStruct.new(info: nil, error: nil)) }

  before do
    VagrantDockerNetworksManager::UiHelpers.setup_i18n!
    allow(VagrantDockerNetworksManager::Util).to receive(:docker_available?).and_return(true)
  end

  def run(argv)
    cmd = described_class.new(argv, env)
    out, err, code = capture_io { cmd.execute }
    [code, out, err]
  end

  it "version --json renvoie la version" do
    code, out, _err = run(%w[version --json])
    expect(code).to eq(0)
    j = JSON.parse(out)
    expect(j["status"]).to eq("success")
    expect(j["data"]["version"]).to eq(VagrantDockerNetworksManager::VERSION)
  end

  it "init --json crée un réseau quand tout est OK" do
    allow(VagrantDockerNetworksManager::Util).to receive(:docker_network_exists?).and_return(false)
    allow(VagrantDockerNetworksManager::Util).to receive(:valid_subnet?).and_return(true)
    allow(VagrantDockerNetworksManager::Util).to receive(:docker_subnet_conflicts?).and_return(false)
    allow(VagrantDockerNetworksManager::Util).to receive(:sh!).and_return(true)

    code, out, _err = run(%w[init netx 10.1.2.0/24 --json])
    expect(code).to eq(0)
    j = JSON.parse(out)
    expect(j["status"]).to eq("success")
    expect(j.dig("data","name")).to eq("netx")
    expect(j.dig("data","subnet")).to eq("10.1.2.0/24")
  end

  it "destroy --json supprime le réseau et remonte la liste des conteneurs déconnectés" do
    allow(VagrantDockerNetworksManager::Util).to receive(:docker_network_exists?).with("netx").and_return(true)
    inspect_json = [
      { "Containers" => {
          "id1" => { "Name" => "c1" },
          "id2" => { "Name" => "c2" }
        } }
    ].to_json
    allow(Open3).to receive(:capture3).with("docker", "network", "inspect", "netx")
      .and_return([inspect_json, "", instance_double(Process::Status, success?: true)])
    allow(VagrantDockerNetworksManager::Util).to receive(:sh!).and_return(true)

    code, out, _err = run(%w[destroy netx --json])
    expect(code).to eq(0)
    j = JSON.parse(out)
    expect(j["status"]).to eq("success")
  end

  it "list --json renvoie une liste vide proprement" do
    allow(VagrantDockerNetworksManager::Util).to receive(:list_plugin_networks).and_return([])
    code, out, _err = run(%w[list --json])
    expect(code).to eq(0)
    j = JSON.parse(out)
    expect(j["status"]).to eq("success")
    expect(j["data"]["count"]).to eq(0)
    expect(j["data"]["items"]).to eq([])
  end

  it "rename --json avec même subnet reconstruit et reconnecte" do
    allow(VagrantDockerNetworksManager::Util).to receive(:docker_network_exists?).with("old").and_return(true)
    allow(VagrantDockerNetworksManager::Util).to receive(:docker_network_exists?).with("new").and_return(false)

    body = [{
      "Driver"=>"bridge",
      "IPAM"=>{"Config"=>[{"Subnet"=>"172.28.100.0/24"}]},
      "Containers"=>{"a"=>{"Name"=>"ca"},"b"=>{"Name"=>"cb"}}
    }].to_json
    allow(Open3).to receive(:capture3).with("docker", "network", "inspect", "old")
      .and_return([body, "", instance_double(Process::Status, success?: true)])

    allow(VagrantDockerNetworksManager::Util).to receive(:valid_subnet?).and_return(true)
    allow(VagrantDockerNetworksManager::Util).to receive(:normalize_cidr).and_call_original
    allow(VagrantDockerNetworksManager::Util).to receive(:docker_subnet_conflicts?).and_return(false)
    allow(VagrantDockerNetworksManager::Util).to receive(:sh!).and_return(true)

    code, out, _err = run(%w[rename old new --json])
    expect(code).to eq(0)
    j = JSON.parse(out)
    expect(j["status"]).to eq("success")
    expect(j["data"]["old"]).to eq("old")
    expect(j["data"]["new"]).to eq("new")
  end
end
