# frozen_string_literal: true

require "vagrant-docker-networks-manager/helpers"

RSpec.describe VagrantDockerNetworksManager::UiHelpers do
  before do
    described_class.setup_i18n!
  end

  it "change de locale et charge les traductions" do
    expect { described_class.set_locale!("fr") }.not_to raise_error
    expect(I18n.locale).to eq(:fr)
  end

  it "refuse une locale non supportée" do
    expect { described_class.set_locale!("zz") }.to raise_error(described_class::UnsupportedLocaleError)
  end

  it "t! lève une erreur sur une clé messages.* manquante" do
    described_class.set_locale!("en")
    expect {
      described_class.t!("messages.this_key_should_not_exist")
    }.to raise_error(described_class::MissingTranslationError)
  end

  it "retourne les bons emojis" do
    expect(described_class.e(:success)).to eq("✅")
    expect(described_class.e(:unknown)).to eq("")
  end
end
