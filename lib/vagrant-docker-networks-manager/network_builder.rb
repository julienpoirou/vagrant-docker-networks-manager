# frozen_string_literal: true

require "shellwords"

module VagrantDockerNetworksManager
  class NetworkBuilder
    PLUGIN_LABEL = "com.vagrant.plugin"
    PLUGIN_NAME  = "docker_networks_manager"

    def initialize(config, machine_id: nil)
      @config     = config
      @machine_id = machine_id
    end

    # Builds docker network create arguments from plugin configuration.
    #
    # Labels are the ownership contract used later for safe adoption and cleanup.
    #
    # @return [Array<String>] Arguments passed after `docker`.
    def build_create_command_args
      labels = { PLUGIN_LABEL => PLUGIN_NAME }
      labels["com.vagrant.machine_id"] = @machine_id if @machine_id

      self.class.create_args(
        name: @config.network_name.to_s,
        driver: @config.network_type,
        labels: labels,
        ipam: [{ subnet: @config.network_subnet,
                 gateway: @config.network_gateway,
                 ip_range: @config.ip_range }],
        ipv6: truthy?(@config.enable_ipv6),
        attachable: truthy?(@config.network_attachable),
        parent: @config.network_parent
      )
    end

    def build_create_command
      build_create_command_args.shelljoin
    end

    # Builds arguments for `docker network create`.
    #
    # Accepts both plugin config keys and Docker inspect-style IPAM keys so
    # callers can create fresh networks or recreate existing networks from
    # inspected state.
    #
    # @param name [String] Docker network name.
    # @param driver [String, nil] Docker network driver.
    # @param labels [Hash{String=>String}] Docker labels to attach to the network.
    # @param ipam [Array<Hash>] IPAM configuration hashes.
    # @param ipv6 [Boolean] Whether to enable IPv6.
    # @param attachable [Boolean] Whether standalone containers can attach.
    # @param parent [String, nil] Parent interface for macvlan/ipvlan.
    # @return [Array<String>] Arguments passed after `docker`.
    def self.create_args(name:, driver: nil, labels: {}, ipam: [],
                         ipv6: false, attachable: false, parent: nil)
      args = ["network", "create"]

      labels.each { |k, v| args += ["--label", "#{k}=#{v}"] if k && v }
      args += ["--driver", driver] if present?(driver)

      Array(ipam).each do |c|
        subnet   = c[:subnet]   || c["Subnet"]
        gateway  = c[:gateway]  || c["Gateway"]
        ip_range = c[:ip_range] || c["IPRange"]
        args += ["--subnet",   subnet]   if present?(subnet)
        args += ["--gateway",  gateway]  if present?(gateway)
        args += ["--ip-range", ip_range] if present?(ip_range)
      end

      args << "--ipv6"       if ipv6
      args << "--attachable" if attachable
      args += ["--opt", "parent=#{parent}"] if %w[macvlan ipvlan].include?(driver.to_s) && present?(parent)

      args << name.to_s
      args
    end

    def self.present?(val)
      !val.nil? && !(val.respond_to?(:empty?) && val.empty?)
    end

    private

    def present?(val)
      self.class.present?(val)
    end

    def truthy?(val)
      val == true
    end
  end
end
