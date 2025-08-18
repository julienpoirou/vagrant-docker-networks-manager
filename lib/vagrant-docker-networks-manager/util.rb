# frozen_string_literal: true

require "open3"
require "json"
require "ipaddr"
require "shellwords"

module VagrantDockerNetworksManager
  module Util
    module_function

    def sh!(*args)
      if ENV["VDNM_VERBOSE"] == "1"
        printable = ["docker", *args].map(&:to_s).shelljoin
        $stderr.puts("[VDNM] #{printable}")
        system("docker", *args)
      else
        system("docker", *args, out: File::NULL, err: :out)
      end
    end

    def docker_available?
      _out, _err, status = Open3.capture3("docker", "info")
      status.success?
    rescue
      false
    end

    def docker_network_exists?(name)
      out, _err, st = Open3.capture3("docker", "network", "ls", "--format", "{{.Name}}")
      st.success? && out.split.include?(name)
    end

    def read_network_labels(name)
      out, _err, st = Open3.capture3("docker", "network", "inspect", name, "--format", "{{json .Labels}}")
      return {} unless st.success?
      JSON.parse(out.to_s.strip) rescue {}
    end

    def inspect_networks_batched(ids_or_names)
      result = {}
      ids_or_names.each_slice(50) do |chunk|
        out, _e, st = Open3.capture3("docker", "network", "inspect", *chunk)
        next unless st.success?
        JSON.parse(out).each do |net|
          subs = (net.dig("IPAM","Config") || []).map { |c| c["Subnet"] }.compact
          cons = (net["Containers"] || {}).size
          key  = net["Id"] || net["Name"]
          result[key] = { subnets: subs, containers_count: cons }
          result[net["Name"]] ||= result[key]
        end
      end
      result
    rescue
      {}
    end

    def list_plugin_networks
      out, _err, st = Open3.capture3(
        "docker", "network", "ls",
        "--filter", "label=com.vagrant.plugin=docker_networks_manager",
        "--format", "{{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}"
      )
      return [] unless st.success?

      rows = out.lines.map do |line|
        id, name, driver, scope = line.strip.split("\t", 4)
        { id: id, name: name, driver: driver, scope: scope }
      end

      details = inspect_networks_batched(rows.map { |r| r[:name] })
      rows.each do |r|
        subs = details.dig(r[:name], :subnets) || []
        r[:subnets] = subs.empty? ? "-" : subs.join(", ")
      end

      rows
    rescue
      []
    end

    def list_plugin_networks_detailed
      out, _err, st = Open3.capture3(
        "docker", "network", "ls",
        "--filter", "label=com.vagrant.plugin=docker_networks_manager",
        "--format", "{{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}"
      )
      return [] unless st.success?

      rows = out.lines.map { |line|
        id, name, driver, scope = line.strip.split("\t", 4)
        { id: id, name: name, driver: driver, scope: scope }
      }

      details = inspect_networks_batched(rows.map { |r| r[:name] })
      rows.each do |r|
        r[:subnets]    = details.dig(r[:name], :subnets) || []
        r[:containers] = details.dig(r[:name], :containers_count) || 0
      end
      rows
    end

    def valid_subnet?(cidr)
      ip_str, mask_str = cidr.to_s.split("/", 2)
      return false unless ip_str && mask_str && mask_str =~ /^\d+$/ && (0..32).include?(mask_str.to_i)
      ip = IPAddr.new(ip_str) rescue nil
      return false unless ip && ip.ipv4?
      (ip.mask(mask_str.to_i).to_s == ip_str)
    rescue
      false
    end

    def normalize_cidr(cidr)
      ip_str, mask_str = cidr.to_s.split("/", 2)
      return nil unless ip_str && mask_str && mask_str =~ /^\d+$/ && (0..32).include?(mask_str.to_i)
      ip = IPAddr.new(ip_str) rescue nil
      return nil unless ip&.ipv4?
      "#{ip.mask(mask_str.to_i)}/#{mask_str.to_i}"
    rescue
      nil
    end

    def cidr_overlap?(a, b)
      ip_a, mask_a = a.to_s.split("/", 2); ip_b, mask_b = b.to_s.split("/", 2)
      return false unless mask_a && mask_b
      na = IPAddr.new(ip_a).mask(mask_a.to_i)
      nb = IPAddr.new(ip_b).mask(mask_b.to_i)
      na.include?(IPAddr.new(ip_b)) || nb.include?(IPAddr.new(ip_a))
    rescue
      false
    end

    def each_docker_cidr(ignore_network: nil)
      out, _e, st = Open3.capture3("docker", "network", "ls", "-q")
      return [] unless st.success?
      out.split.each_slice(50).flat_map do |chunk|
        o, _e2, st2 = Open3.capture3("docker", "network", "inspect", *chunk)
        next [] unless st2.success?
        JSON.parse(o).filter_map do |net|
          next if ignore_network && net["Name"] == ignore_network
          (net.dig("IPAM","Config") || []).map { |cfg| normalize_cidr(cfg["Subnet"]) }.compact
        end.flatten
      end
    end

    def docker_subnet_conflicts?(target_cidr, ignore_network: nil)
      t_norm = normalize_cidr(target_cidr)
      return false unless t_norm
      each_docker_cidr(ignore_network: ignore_network).any? { |c| cidr_overlap?(t_norm, c) }
    end
  end
end
