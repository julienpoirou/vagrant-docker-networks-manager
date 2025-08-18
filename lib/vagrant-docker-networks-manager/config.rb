# frozen_string_literal: true

require "ipaddr"
require_relative "helpers"

module VagrantDockerNetworksManager
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
      VagrantDockerNetworksManager::UiHelpers.setup_i18n! rescue nil
      errors = []

      unless @network_name.is_a?(String) && !@network_name.strip.empty? && docker_name?(@network_name)
        errors << ::I18n.t("errors.invalid_name")
      end

      unless ipv4_cidr_aligned?(@network_subnet)
        errors << ::I18n.t("errors.invalid_subnet")
      end

      unless @network_type.is_a?(String) && %w[bridge macvlan].include?(@network_type)
        errors << ::I18n.t("errors.invalid_type")
      end

      if present?(@network_gateway)
        if !ipv4?(@network_gateway)
          errors << ::I18n.t("errors.invalid_gateway")
        elsif ipv4_cidr_aligned?(@network_subnet) && !gateway_host_addr?(@network_subnet, @network_gateway)
          errors << ::I18n.t("errors.invalid_gateway")
        end
      end

      if present?(@network_parent) && !@network_parent.is_a?(String)
        errors << ::I18n.t("errors.invalid_parent")
      end

      if @network_type.to_s == "macvlan" && !present?(@network_parent)
        errors << ::I18n.t("errors.invalid_parent")
      end

      unless [true, false].include?(@network_attachable)
        errors << ::I18n.t("errors.invalid_attachable")
      end

      unless [true, false].include?(@enable_ipv6)
        errors << ::I18n.t("errors.invalid_ipv6")
      end

      if present?(@ip_range)
        if !ipv4_cidr?(@ip_range)
          errors << ::I18n.t("errors.invalid_ip_range")
        elsif ipv4_cidr_aligned?(@network_subnet) && !cidr_within_cidr?(@network_subnet, @ip_range)
          errors << ::I18n.t("errors.invalid_ip_range")
        end
      end

      unless [true, false].include?(@cleanup_on_destroy)
        errors << ::I18n.t("errors.invalid_cleanup")
      end

      unless @locale.is_a?(String) && %w[fr en].include?(@locale.to_s[0,2].downcase)
        errors << ::I18n.t("errors.invalid_locale")
      end

      { "vagrant-docker-networks-manager" => errors }
    end

    private

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
