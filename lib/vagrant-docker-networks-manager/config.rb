# frozen_string_literal: true

require "ipaddr"
require_relative "helpers"

module VagrantDockerNetworksManager
  # Vagrant configuration for Docker network creation and cleanup.
  #
  # @!attribute network_name
  #   @return [String] Docker network name.
  # @!attribute network_subnet
  #   @return [String] IPv4 subnet in CIDR notation.
  # @!attribute network_type
  #   @return [String] Docker network driver.
  # @!attribute network_gateway
  #   @return [String, nil] Optional gateway IP address.
  # @!attribute network_parent
  #   @return [String, nil] Parent interface for macvlan networks.
  # @!attribute cleanup_on_destroy
  #   @return [Boolean] Whether to remove the network during `vagrant destroy`.
  class Config < Vagrant.plugin("2", :config)
    attr_accessor :network_name, :network_subnet, :network_type, :network_gateway,
                  :network_parent, :network_attachable, :enable_ipv6, :ip_range,
                  :cleanup_on_destroy, :locale

    def initialize
      @network_name       = UNSET_VALUE
      @network_subnet     = UNSET_VALUE
      @network_type       = UNSET_VALUE
      @network_gateway    = UNSET_VALUE
      @network_parent     = UNSET_VALUE
      @network_attachable = UNSET_VALUE
      @enable_ipv6        = UNSET_VALUE
      @ip_range           = UNSET_VALUE
      @cleanup_on_destroy = UNSET_VALUE
      @locale             = UNSET_VALUE
    end

    def finalize!
      @network_name       = "network_lo1"       if @network_name       == UNSET_VALUE
      @network_subnet     = "172.28.100.0/26"   if @network_subnet     == UNSET_VALUE
      @network_type       = "bridge"            if @network_type       == UNSET_VALUE
      @network_gateway    = "172.28.100.1"      if @network_gateway    == UNSET_VALUE
      @network_parent     = nil                 if @network_parent     == UNSET_VALUE
      @network_attachable = false               if @network_attachable == UNSET_VALUE
      @enable_ipv6        = false               if @enable_ipv6        == UNSET_VALUE
      @ip_range           = nil                 if @ip_range           == UNSET_VALUE
      @cleanup_on_destroy = true                if @cleanup_on_destroy == UNSET_VALUE
      @locale             = "en"                if @locale             == UNSET_VALUE
    end

    def validate(_machine)
      setup_i18n_safely

      keys = [
        name_error, subnet_error, type_error, gateway_error, parent_error,
        attachable_error, ipv6_error, ip_range_error, cleanup_error, locale_error
      ].compact

      { "vagrant-docker-networks-manager" => keys.map { |key| UiHelpers.t(key) } }
    end

    private

    def setup_i18n_safely
      VagrantDockerNetworksManager::UiHelpers.setup_i18n!
    rescue StandardError
      nil
    end

    def name_error
      return if @network_name.is_a?(String) && !@network_name.strip.empty? && docker_name?(@network_name)

      "errors.invalid_name"
    end

    def subnet_error
      "errors.invalid_subnet" unless ipv4_cidr_aligned?(@network_subnet)
    end

    def type_error
      "errors.invalid_type" unless @network_type.is_a?(String) && %w[bridge macvlan].include?(@network_type)
    end

    def gateway_error
      return unless present?(@network_gateway)
      return "errors.invalid_gateway" unless ipv4?(@network_gateway)
      return "errors.invalid_gateway" if ipv4_cidr_aligned?(@network_subnet) &&
                                         !gateway_host_addr?(@network_subnet, @network_gateway)

      nil
    end

    def parent_error
      return "errors.invalid_parent" if present?(@network_parent) && !@network_parent.is_a?(String)
      return "errors.invalid_parent" if @network_type.to_s == "macvlan" && !present?(@network_parent)

      nil
    end

    def attachable_error
      "errors.invalid_attachable" unless [true, false].include?(@network_attachable)
    end

    def ipv6_error
      "errors.invalid_ipv6" unless [true, false].include?(@enable_ipv6)
    end

    def ip_range_error
      return unless present?(@ip_range)
      return "errors.invalid_ip_range" unless ipv4_cidr?(@ip_range)
      return "errors.invalid_ip_range" if ipv4_cidr_aligned?(@network_subnet) &&
                                          !cidr_within_cidr?(@network_subnet, @ip_range)

      nil
    end

    def cleanup_error
      "errors.invalid_cleanup" unless [true, false].include?(@cleanup_on_destroy)
    end

    def locale_error
      return if @locale.is_a?(String) && %w[fr en].include?(@locale.to_s[0, 2].downcase)

      "errors.invalid_locale"
    end

    def present?(val)
      !val.nil? && !(val.respond_to?(:empty?) && val.empty?)
    end
  
    def ipv4?(str)
      ip = IPAddr.new(str) rescue nil
      ip&.ipv4? ? true : false
    end

    def ipv4_cidr?(str)
      ip_str, mask_str = str.to_s.split("/", 2)
      return false unless ip_str && mask_str&.match?(/^\d+$/)
      m = mask_str.to_i
      return false unless (0..32).include?(m)
      ip = IPAddr.new(ip_str) rescue nil
      ip&.ipv4? ? true : false
    rescue
      false
    end

    def ipv4_cidr_aligned?(str)
      ip_str, mask_str = str.to_s.split("/", 2)
      return false unless ip_str && mask_str&.match?(/^\d+$/)
      m = mask_str.to_i
      return false unless (0..32).include?(m)
      ip = IPAddr.new(ip_str) rescue nil
      return false unless ip&.ipv4?
      ip.mask(m).to_s == ip_str
    rescue
      false
    end

    def gateway_host_addr?(cidr, gw)
      net = IPAddr.new(cidr) rescue nil
      ip  = IPAddr.new(gw)   rescue nil
      return false unless net&.ipv4? && ip&.ipv4? && net.include?(ip)
      mask = cidr.split("/")[1].to_i
      network = IPAddr.new(net.to_range.first.to_s).mask(mask)
      broadcast = IPAddr.new(net.to_range.last.to_s)
      ip != network && ip != broadcast
    rescue
      false
    end

    def cidr_within_cidr?(outer, inner)
      outer_ip, outer_mask = outer.to_s.split("/", 2)
      inner_ip, inner_mask = inner.to_s.split("/", 2)
      return false unless outer_ip && inner_ip && outer_mask&.match?(/^\d+$/) && inner_mask&.match?(/^\d+$/)

      om = outer_mask.to_i
      im = inner_mask.to_i
      return false unless (0..32).include?(om) && (0..32).include?(im)
      return false unless om <= im

      outer_net = IPAddr.new(outer_ip).mask(om) rescue nil
      inner_as_outer = IPAddr.new(inner_ip).mask(om) rescue nil
      outer_net&.ipv4? && inner_as_outer&.ipv4? && (inner_as_outer.to_s == outer_net.to_s)
    rescue
      false
    end

    def docker_name?(s)
      s.is_a?(String) && s.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,126}\z/)
    end
  end
end
