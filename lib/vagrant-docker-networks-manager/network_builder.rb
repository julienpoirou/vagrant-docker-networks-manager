# frozen_string_literal: true

require "shellwords"

module VagrantDockerNetworksManager
  class NetworkBuilder
    def initialize(config, machine_id: nil)
      @config     = config
      @machine_id = machine_id
    end

    def build_create_command_args
      args = ["network", "create"]

      args += ["--label", "com.vagrant.plugin=docker_networks_manager"]
      args += ["--label", "com.vagrant.machine_id=#{@machine_id}"] if @machine_id
      args += ["--driver", @config.network_type] if present?(@config.network_type)
      args += ["--subnet",  @config.network_subnet]  if present?(@config.network_subnet)
      args += ["--gateway", @config.network_gateway] if present?(@config.network_gateway)
      args += ["--ip-range", @config.ip_range]       if present?(@config.ip_range)
      args << "--ipv6"       if truthy?(@config.enable_ipv6)
      args << "--attachable" if truthy?(@config.network_attachable)
      if @config.network_type.to_s == "macvlan" && present?(@config.network_parent)
        args += ["--opt", "parent=#{@config.network_parent}"]
      end
      args << @config.network_name.to_s
      args
    end

    def build_create_command
      build_create_command_args.shelljoin
    end

    private

    def present?(val)
      !val.nil? && !(val.respond_to?(:empty?) && val.empty?)
    end

    def truthy?(val)
      val == true
    end
  end
end
