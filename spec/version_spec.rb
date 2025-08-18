# frozen_string_literal: true

require "vagrant-docker-networks-manager/version"

RSpec.describe VagrantDockerNetworksManager::VERSION do
  it "est une chaîne non vide" do
    expect(VagrantDockerNetworksManager::VERSION).to be_a(String)
    expect(VagrantDockerNetworksManager::VERSION).not_to be_empty
  end
end
