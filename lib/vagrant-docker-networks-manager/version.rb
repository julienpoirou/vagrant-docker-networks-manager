# frozen_string_literal: true

module VagrantDockerNetworksManager
  VERSION = begin
    path = File.expand_path("VERSION", __dir__)
    File.exist?(path) ? File.read(path).strip : "0.0.0"
  rescue
    "0.0.0"
  end
end
