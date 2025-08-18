# frozen_string_literal: true

require "vagrant-docker-networks-manager/util"

RSpec.describe VagrantDockerNetworksManager::Util do
  describe ".normalize_cidr" do
    it "normalise l'adresse réseau" do
      expect(described_class.normalize_cidr("192.168.1.10/24")).to eq("192.168.1.0/24")
    end

    it "retourne nil si invalide" do
      expect(described_class.normalize_cidr("bad/24")).to be_nil
      expect(described_class.normalize_cidr("192.168.1.1/not")).to be_nil
    end
  end

  describe ".valid_subnet?" do
    it "accepte un CIDR IPv4 aligné" do
      expect(described_class.valid_subnet?("10.0.0.0/24")).to be true
    end

    it "refuse un CIDR non aligné" do
      expect(described_class.valid_subnet?("10.0.0.1/24")).to be false
    end

    it "refuse des valeurs invalides" do
      expect(described_class.valid_subnet?("nope")).to be false
    end
  end

  describe ".cidr_overlap?" do
    it "détecte le chevauchement" do
      expect(described_class.cidr_overlap?("192.168.1.0/24", "192.168.1.128/25")).to be true
      expect(described_class.cidr_overlap?("10.0.0.0/24", "10.0.1.0/24")).to be false
    end
  end

  describe ".docker_subnet_conflicts?" do
    it "signale un conflit si un CIDR existant chevauche la cible" do
      allow(described_class).to receive(:each_docker_cidr).and_return(["172.28.0.0/16"])
      expect(described_class.docker_subnet_conflicts?("172.28.100.0/24")).to be true
      expect(described_class.docker_subnet_conflicts?("10.0.0.0/24")).to be false
    end
  end
end
