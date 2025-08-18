# frozen_string_literal: true

require "vagrant-docker-networks-manager/config"
require "i18n"

RSpec.describe VagrantDockerNetworksManager::Config do
  before do
    I18n.enforce_available_locales = false
    I18n.backend.store_translations(:en, errors: Hash.new("err"))
    I18n.locale = :en
  end

  it "applique les valeurs par défaut au finalize!" do
    cfg = described_class.new
    cfg.finalize!
    expect(cfg.network_name).to eq("network_lo1")
    expect(cfg.network_type).to eq("bridge")
    expect(cfg.network_subnet).to eq("172.28.100.0/26")
    expect(cfg.network_gateway).to eq("172.28.100.1")
    expect(cfg.network_attachable).to be false
    expect(cfg.enable_ipv6).to be false
    expect(cfg.cleanup_on_destroy).to be true
    expect(cfg.locale).to eq("en")
  end

  it "valide une configuration correcte" do
    cfg = described_class.new
    cfg.finalize!
    cfg.network_name   = "net_ok-1"
    cfg.network_subnet = "10.10.0.0/24"
    cfg.network_gateway = "10.10.0.1"
    errors = cfg.validate(nil).values.flatten
    expect(errors).to be_empty
  end

  it "rejette un nom vide et un nom hors contrainte Docker" do
    cfg = described_class.new
    cfg.finalize!
    cfg.network_name = ""
    errs = cfg.validate(nil)["vagrant-docker-networks-manager"]
    expect(errs).not_to be_empty

    cfg.network_name = ("a" * 1) + ("b" * 127)
    errs = cfg.validate(nil)["vagrant-docker-networks-manager"]
    expect(errs).not_to be_empty
  end

  it "rejette ip_range hors du subnet" do
    cfg = described_class.new
    cfg.finalize!
    cfg.network_subnet = "10.0.0.0/24"
    cfg.ip_range       = "10.0.1.0/24"
    errs = cfg.validate(nil)["vagrant-docker-networks-manager"]
    expect(errs).not_to be_empty
  end

  it "rejette une gateway hors du réseau ou adresse réseau/broadcast" do
    cfg = described_class.new
    cfg.finalize!
    cfg.network_subnet  = "192.168.10.0/24"
    cfg.network_gateway = "192.168.11.1"
    errs = cfg.validate(nil)["vagrant-docker-networks-manager"]
    expect(errs).not_to be_empty

    cfg.network_gateway = "192.168.10.0"
    errs = cfg.validate(nil)["vagrant-docker-networks-manager"]
    expect(errs).not_to be_empty
  end

  it "exige network_parent pour macvlan" do
    cfg = described_class.new
    cfg.finalize!
    cfg.network_type = "macvlan"
    cfg.network_parent = nil
    errs = cfg.validate(nil)["vagrant-docker-networks-manager"]
    expect(errs).not_to be_empty
  end
end
