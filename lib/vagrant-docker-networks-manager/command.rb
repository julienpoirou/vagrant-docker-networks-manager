# frozen_string_literal: true

require "json"
require "ipaddr"
require "open3"
require "optparse"
require "shellwords"
require_relative "network_builder"
require_relative "helpers"
require_relative "util"
require_relative "version"

module VagrantDockerNetworksManager
  InitConfig = Struct.new(
    :network_name, :network_type, :network_subnet, :network_gateway,
    :network_parent, :network_attachable, :enable_ipv6, :ip_range
  )

  NetAttrs = Struct.new(:driver, :ipam_cfgs, :subnets, :containers, :ipv6, :attachable, :parent, :labels)

  class Command < Vagrant.plugin("2", :command)
    DRIVERS = %w[bridge macvlan ipvlan].freeze

    def execute
      argv = @argv.dup
      @opts = {
        quiet: false, no_emoji: false, json: false, yes: false,
        lang: nil, with_containers: false, driver: nil, parent: nil
      }

      UiHelpers.setup_i18n!

      OptionParser.new do |o|
        o.on("--quiet", "Reduce output (hide info)")               { @opts[:quiet] = true }
        o.on("--no-emoji", "Disable emojis in output")             { @opts[:no_emoji] = true }
        o.on("--json", "Normalized JSON output for all commands")  { @opts[:json] = true }
        o.on("--yes", "-y", "Auto-confirm destructive operations") { @opts[:yes] = true }
        o.on("--lang LANG", "Force language: en|fr")               { |v| @opts[:lang] = v }
        o.on("--driver DRIVER", "init: network driver bridge|macvlan|ipvlan") { |v| @opts[:driver] = v }
        o.on("--parent IFACE", "init: parent host interface (macvlan/ipvlan)") { |v| @opts[:parent] = v }
        o.on(
          '--with-containers',
          'When destroying a network, also remove attached containers'
        ) { @opts[:with_containers] = true }
      end.permute!(argv)

      begin
        if @opts[:lang]
          UiHelpers.set_locale!(@opts[:lang])
        elsif ENV["VDNM_LANG"]
          UiHelpers.set_locale!(ENV["VDNM_LANG"])
        else
          UiHelpers.setup_i18n!
        end
      rescue UiHelpers::UnsupportedLocaleError, UiHelpers::MissingTranslationError => ex
        err(ex.message)
        return 1
      end

      subcmd       = argv[0]
      network_name = argv[1]
      subnet       = argv[2]

      needs_docker = %w[init destroy info reload list prune rename].include?(subcmd)
      if needs_docker && !Util.docker_available?
        return json_or_text("precheck", error: I18n.t('vdnm.errors.docker_unavailable'), code: 2)
      end

      case subcmd
      when "init"    then cmd_init(network_name, subnet)
      when "destroy" then cmd_destroy(network_name)
      when "info"    then cmd_info(network_name)
      when "reload"  then cmd_reload(network_name)
      when "prune"   then cmd_prune(network_name)
      when "list"    then cmd_list
      when "rename"  then cmd_rename(argv)
      when "version" then cmd_version
      when "help"    then UiHelpers.print_topic_help(argv[1]); 0
      else           json_or_text("unknown", error: I18n.t("vdnm.errors.unknown_command"), code: 1)
      end
    end

    private

    def cmd_init(network_name, subnet)
      return json_or_text("init", error: I18n.t("vdnm.usage.init"), code: 1) if network_name.nil? || subnet.nil?
      return json_or_text(
        'init',
        error: I18n.t('vdnm.errors.network_exists'),
        data: { name: network_name },
        code: 1
      ) if Util.docker_network_exists?(network_name)
      return json_or_text(
        'init',
        error: I18n.t('vdnm.errors.invalid_subnet'),
        data: { name: subnet },
        code: 1
      ) unless Util.valid_subnet?(subnet)
      return json_or_text(
        'init',
        error: I18n.t('vdnm.errors.subnet_in_use'),
        data: { name: subnet },
        code: 1
      ) if Util.docker_subnet_conflicts?(subnet)
      return json_or_text(
        "init",
        error: I18n.t("vdnm.errors.invalid_name"),
        data: { name: network_name },
        code: 1
      ) unless network_name =~ /\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,126}\z/

      driver = (@opts[:driver] || "bridge").to_s.downcase
      parent = @opts[:parent]
      driver_error = validate_init_driver(driver, parent)
      return driver_error if driver_error

      cfg  = InitConfig.new(network_name, driver, subnet, nil, parent, false, false, nil)
      args = NetworkBuilder.new(cfg).build_create_command_args
      say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.create_network', name: network_name, subnet: subnet)}"
      ok = Util.sh!(*args)
      if ok
        json_or_text("init", data: { name: network_name, subnet: subnet, driver: driver })
      else
        json_or_text('init', error: I18n.t("vdnm.errors.create_failed"), data: { name: network_name, subnet: subnet }, code: 1)
      end
    end

    def validate_init_driver(driver, parent)
      unless DRIVERS.include?(driver)
        return json_or_text("init", error: I18n.t("vdnm.errors.invalid_driver"), data: { driver: driver }, code: 1)
      end
      if %w[macvlan ipvlan].include?(driver) && (parent.nil? || parent.to_s.strip.empty?)
        return json_or_text("init", error: I18n.t("vdnm.errors.parent_required"), data: { driver: driver }, code: 1)
      end

      nil
    end

    def cmd_destroy(network_name)
      return json_or_text("destroy", error: I18n.t("vdnm.usage.destroy"), code: 1) if network_name.nil?
      return json_or_text(
        "destroy",
        error: I18n.t("vdnm.errors.network_not_found"),
        data: { name: network_name },
        code: 1
      ) unless Util.docker_network_exists?(network_name)

      info       = inspect_network(network_name)
      containers = info ? network_attrs(info).containers : []

      unless @opts[:with_containers]
        guard = guard_network_mode("destroy", network_name, containers, { name: network_name })
        return guard if guard
      end

      prompt_key = @opts[:with_containers] ? "prompts.delete_network_with_containers" : "prompts.delete_network_only"
      stop = require_confirmation("destroy", I18n.t(prompt_key, name: network_name, count: containers.size),
                                  { name: network_name })
      return stop if stop

      teardown_containers(network_name, containers)

      say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.remove_network', name: network_name)}"
      ok = Util.sh!("network", "rm", network_name)
      removed = @opts[:with_containers] ? containers : []
      if ok
        json_or_text("destroy", data: { name: network_name, removed_containers: removed })
      else
        json_or_text("destroy", error: I18n.t("vdnm.errors.remove_failed"),
          data: { name: network_name, removed_containers: removed }, code: 1)
      end
    end

    def teardown_containers(network_name, containers)
      containers.each do |c|
        say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.disconnect_container', name: c)}"
        Util.sh!("network", "disconnect", "--force", network_name, c)
        next unless @opts[:with_containers]

        say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.remove_container', name: c)}"
        Util.sh!("rm", "-f", c)
      end
    end

    def cmd_info(network_name)
      return json_or_text("info", error: I18n.t("vdnm.usage.info"), code: 1) if network_name.nil?
      return json_or_text(
        "info",
        error: I18n.t("vdnm.errors.network_not_found"),
        data: { name: network_name },
        code: 1
      ) unless Util.docker_network_exists?(network_name)

      info = inspect_network(network_name)
      return json_or_text("info", error: I18n.t("vdnm.errors.inspect_failed"), data: { name: network_name }, code: 1) unless info

      @opts[:json] ? info_json(info) : info_text(info, network_name)
    end

    def info_json(info)
      payload = {
        network: {
          "Name"       => info["Name"],
          "Id"         => info["Id"],
          "Driver"     => info["Driver"],
          "Subnets"    => (info.dig("IPAM", "Config") || []).map { |c| c["Subnet"] }.compact,
          "Containers" => (info["Containers"] || {}).values.map do |c|
            { "Name" => c["Name"], "IPv4" => c["IPv4Address"] }
          end
        }
      }
      json_emit("info", status: "success", data: payload)
    end

    def info_text(info, network_name)
      say "#{UiHelpers.e(:info, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.info_header', name: network_name)}"
      puts "  • ID: #{info['Id'][0...12]}"
      puts "  • Driver: #{info['Driver']}"
      puts "  • Subnet(s): #{(info.dig('IPAM', 'Config') || []).map { |c| c['Subnet'] }.compact.join(', ')}"
      cons = info["Containers"] || {}
      if cons.empty?
        puts "  • Connected containers: (none)"
      else
        puts "  • Connected containers:"
        cons.each_value { |c| puts "    • #{c['Name']} (IP: #{c['IPv4Address']})" }
      end
      0
    end

    def cmd_reload(network_name)
      return json_or_text("reload", error: I18n.t("vdnm.usage.reload"), code: 1) if network_name.nil?
      return json_or_text(
        "reload",
        error: I18n.t("vdnm.errors.network_not_found"),
        data: { name: network_name },
        code: 1
      ) unless Util.docker_network_exists?(network_name)

      info = inspect_network(network_name)
      return json_or_text("reload", error: I18n.t("vdnm.errors.inspect_failed"), data: { name: network_name }, code: 1) unless info

      attrs = network_attrs(info)

      if ENV["VDNM_SKIP_CONFLICTS"] != "1" &&
         attrs.subnets.any? { |s| Util.docker_subnet_conflicts?(s, ignore_network: network_name) }
        return json_or_text("reload", error: I18n.t("vdnm.errors.subnet_in_use"),
          data: { name: network_name, subnets: attrs.subnets }, code: 1)
      end

      guard = guard_network_mode("reload", network_name, attrs.containers, { name: network_name })
      return guard if guard

      stop = require_confirmation("reload", I18n.t("vdnm.prompts.reload_same", name: network_name), { name: network_name })
      return stop if stop

      disconnect_containers(network_name, attrs.containers)

      say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.remove_network', name: network_name)}"
      unless Util.sh!("network", "rm", network_name)
        return json_or_text("reload", error: I18n.t("vdnm.errors.remove_failed"), data: { name: network_name }, code: 1)
      end

      recreate_code = recreate_same_network(network_name, attrs)
      return recreate_code if recreate_code

      reconnected, failed_reconnect = reconnect_containers(network_name, attrs.containers)
      data = { name: network_name, subnets: attrs.subnets, reconnected: reconnected, failed_reconnect: failed_reconnect }
      if failed_reconnect.any?
        json_or_text("reload", error: I18n.t("vdnm.errors.partial_failure"), data: data, code: 1)
      else
        json_or_text("reload", data: data)
      end
    end

    def recreate_same_network(network_name, attrs)
      # Recreate from inspected state so reload keeps labels, IPAM blocks and
      # driver-specific options that may not exist in the current Vagrant config.
      args = NetworkBuilder.create_args(
        name:       network_name,
        driver:     attrs.driver,
        labels:     attrs.labels,
        ipam:       attrs.ipam_cfgs,
        ipv6:       attrs.ipv6,
        attachable: attrs.attachable,
        parent:     attrs.parent
      )
      subnet_label = attrs.subnets.empty? ? "-" : attrs.subnets.join(", ")
      say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.create_network', name: network_name, subnet: subnet_label)}"
      return nil if Util.sh!(*args)

      rendered = (["docker"] + args).map(&:to_s).shelljoin
      json_or_text("reload",
        error: "#{I18n.t('vdnm.errors.create_failed')} (#{rendered})",
        data: { name: network_name, subnets: attrs.subnets }, code: 1)
    end

    def cmd_prune(target = nil)
      nets = Util.list_plugin_networks_detailed
      return prune_one(nets, target) if target && !target.to_s.strip.empty?

      prune_all(nets)
    end

    def prune_one(nets, target)
      net = nets.find { |n| n[:name] == target }
      return json_or_text("prune", error: I18n.t("vdnm.errors.network_not_found"), data: { name: target }, code: 1) unless net

      if net[:containers].to_i.positive?
        return json_or_text("prune",
          error: I18n.t("vdnm.errors.network_has_containers", name: target, count: net[:containers]),
          data: { name: target, containers: net[:containers] }, code: 1)
      end

      stop = require_confirmation("prune", I18n.t("vdnm.prompts.prune", count: 1), { candidates: [target] })
      return stop if stop

      say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.remove_network', name: target)}" unless @opts[:quiet]
      if Util.sh!("network", "rm", target)
        json_or_text("prune", data: { pruned: 1, items: [target] })
      else
        json_or_text("prune", error: I18n.t("vdnm.errors.remove_failed"), data: { attempted: [target] }, code: 1)
      end
    end

    def prune_all(nets)
      to_delete = nets.select { |n| n[:containers].to_i.zero? }

      if to_delete.empty?
        return json_emit("prune", status: "success", data: { pruned: 0, items: [] }) if @opts[:json]

        msg_key = nets.any? ? "vdnm.messages.prune_all_busy" : "vdnm.messages.prune_none"
        say "#{UiHelpers.e(:info, no_emoji: @opts[:no_emoji])} #{I18n.t(msg_key, count: nets.size)}"
        return 0
      end

      stop = require_confirmation("prune", I18n.t("vdnm.prompts.prune", count: to_delete.size),
                                  { candidates: to_delete.map { |n| n[:name] } })
      return stop if stop

      ok_all = true
      to_delete.each do |n|
        say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.remove_network', name: n[:name])}" unless @opts[:quiet]
        ok_all &&= Util.sh!("network", "rm", n[:name])
      end

      if ok_all
        json_or_text("prune", data: { pruned: to_delete.size, items: to_delete.map { |n| n[:name] } })
      else
        json_or_text("prune",
          error: I18n.t("vdnm.errors.partial_failure"),
          data: { attempted: to_delete.map { |n| n[:name] } },
          code: 1)
      end
    end

    def cmd_list
      nets = Util.list_plugin_networks
      if @opts[:json]
        return json_emit("list", status: "success", data: { count: nets.size, items: nets })
      end

      if nets.empty?
        say "#{UiHelpers.e(:info, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.messages.no_networks')}"
        return 0
      end

      say "#{UiHelpers.e(:info, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.messages.networks_header')}"
      headers  = ["Name", "Driver", "Scope", "Subnet(s)"]
      name_w   = ([headers[0].length] + nets.map { |r| r[:name].length }).max
      driver_w = ([headers[1].length] + nets.map { |r| r[:driver].length }).max
      scope_w  = ([headers[2].length] + nets.map { |r| r[:scope].length }).max
      subnet_w = ([headers[3].length] + nets.map { |r| r[:subnets].length }).max

      header_line = [
        headers[0].ljust(name_w),
        headers[1].ljust(driver_w),
        headers[2].ljust(scope_w),
        headers[3].ljust(subnet_w)
      ].join("  ")
      puts "  #{header_line}"
      puts "  #{"-" * name_w}  #{"-" * driver_w}  #{"-" * scope_w}  #{"-" * subnet_w}"

      nets.sort_by { |r| r[:name] }.each do |r|
        puts "  %-#{name_w}s  %-#{driver_w}s  %-#{scope_w}s  %s" % [r[:name], r[:driver], r[:scope], r[:subnets]]
      end
      0
    end

    def cmd_rename(argv)
      return json_or_text("rename", error: I18n.t("vdnm.usage.rename"), code: 1) if argv.length < 3

      old_name   = argv[1]
      new_name   = argv[2]
      new_subnet = argv[3]

      code = validate_rename_targets(old_name, new_name)
      return code if code

      info = inspect_network(old_name)
      return json_or_text("rename", error: I18n.t("vdnm.errors.inspect_failed"), data: { old: old_name }, code: 1) unless info

      attrs         = network_attrs(info)
      target_subnet = new_subnet || attrs.subnets.first
      return json_or_text(
        "rename",
        error: I18n.t("vdnm.errors.invalid_subnet"),
        data: { subnet: target_subnet },
        code: 1
      ) unless Util.valid_subnet?(target_subnet)

      same_subnet = attrs.subnets.map { |s| Util.normalize_cidr(s) }.compact.include?(Util.normalize_cidr(target_subnet))

      if !same_subnet && Util.docker_subnet_conflicts?(target_subnet, ignore_network: old_name)
        return json_or_text("rename", error: I18n.t("vdnm.errors.subnet_in_use"), data: { subnet: target_subnet }, code: 1)
      end

      guard = guard_network_mode("rename", old_name, attrs.containers, { old: old_name, new: new_name })
      return guard if guard

      stop = require_confirmation("rename", rename_prompt(old_name, new_name, same_subnet),
                                  { old: old_name, new: new_name })
      return stop if stop

      if new_name == old_name || same_subnet
        rename_in_place(old_name, new_name, target_subnet, attrs)
      else
        rename_to_new_subnet(old_name, new_name, target_subnet, attrs)
      end
    end

    def validate_rename_targets(old_name, new_name)
      return json_or_text(
        "rename", error: I18n.t("vdnm.errors.network_not_found"), data: { old: old_name }, code: 1
      ) unless Util.docker_network_exists?(old_name)

      if new_name != old_name && Util.docker_network_exists?(new_name)
        return json_or_text("rename", error: I18n.t("vdnm.errors.target_exists"), data: { new: new_name }, code: 1)
      end

      nil
    end

    def rename_prompt(old_name, new_name, same_subnet)
      if new_name == old_name && same_subnet
        I18n.t("vdnm.prompts.reload_same", name: old_name)
      elsif new_name == old_name && !same_subnet
        I18n.t("vdnm.prompts.reload_network", name: old_name)
      elsif same_subnet
        I18n.t("vdnm.prompts.rename_same_subnet", old: old_name, new: new_name)
      else
        I18n.t("vdnm.prompts.rename_network", old: old_name, new: new_name)
      end
    end

    def rename_in_place(old_name, new_name, target_subnet, attrs)
      disconnect_containers(old_name, attrs.containers)

      say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.remove_network', name: old_name)}"
      return json_or_text("rename", error: I18n.t("vdnm.errors.remove_failed"), data: { name: old_name }, code: 1) unless Util.sh!("network", "rm", old_name)

      return json_or_text("rename", error: I18n.t("vdnm.errors.create_failed"),
        data: { new: new_name, subnet: target_subnet }, code: 1) unless create_subnet_network(new_name, target_subnet, attrs)

      reconnected, failed_reconnect = reconnect_containers(new_name, attrs.containers)
      rename_result(old_name, new_name, target_subnet, reconnected, failed_reconnect)
    end

    def rename_to_new_subnet(old_name, new_name, target_subnet, attrs)
      # Create the replacement network before disconnecting the old one, so
      # containers keep a usable network path if creation fails.
      return json_or_text("rename", error: I18n.t("vdnm.errors.create_failed"),
        data: { new: new_name, subnet: target_subnet }, code: 1) unless create_subnet_network(new_name, target_subnet, attrs)

      reconnected, failed_reconnect = reconnect_containers(new_name, attrs.containers, announce: true)
      disconnect_containers(old_name, reconnected)

      say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.remove_network', name: old_name)}"
      unless Util.sh!("network", "rm", old_name)
        return json_or_text("rename", error: I18n.t("vdnm.errors.remove_failed"), data: {
          old: old_name, new: new_name, subnet: target_subnet,
          reconnected: reconnected, failed_reconnect: failed_reconnect
        }, code: 1)
      end

      rename_result(old_name, new_name, target_subnet, reconnected, failed_reconnect)
    end

    def rename_result(old_name, new_name, target_subnet, reconnected, failed_reconnect)
      data = {
        old: old_name, new: new_name, subnet: target_subnet,
        reconnected: reconnected, failed_reconnect: failed_reconnect
      }
      if failed_reconnect.any?
        json_or_text("rename", error: I18n.t("vdnm.errors.partial_failure"), data: data, code: 1)
      else
        json_or_text("rename", data: data)
      end
    end

    def create_subnet_network(name, subnet, attrs)
      say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.create_network', name: name, subnet: subnet)}"
      args = NetworkBuilder.create_args(
        name:       name,
        driver:     attrs.driver,
        labels:     attrs.labels,
        ipam:       [{ subnet: subnet }],
        ipv6:       attrs.ipv6,
        attachable: attrs.attachable,
        parent:     attrs.parent
      )
      ok = Util.sh!(*args)
      unless ok
        rendered = (["docker"] + args).map(&:to_s).shelljoin
        err("#{UiHelpers.e(:error, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.errors.create_failed')} (#{rendered})")
      end
      ok
    end

    def cmd_version
      if @opts[:json]
        return json_emit("version", status: "success", data: { version: VagrantDockerNetworksManager::VERSION })
      end
      say "#{UiHelpers.e(:version, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.version_line', version: VagrantDockerNetworksManager::VERSION)}"
      0
    end

    def inspect_network(name)
      out, _e, st = Open3.capture3("docker", "network", "inspect", name)
      return nil unless st.success?

      JSON.parse(out).first
    end

    def network_attrs(info)
      ipam_cfgs = info.dig("IPAM", "Config") || []
      labels    = info["Labels"] || {}
      labels["com.vagrant.plugin"] ||= "docker_networks_manager"
      NetAttrs.new(
        info["Driver"] || "bridge",
        ipam_cfgs,
        ipam_cfgs.map { |c| c["Subnet"] }.compact,
        (info["Containers"] || {}).values.map { |c| c["Name"] },
        info["EnableIPv6"],
        info["Attachable"],
        info.fetch("Options", {})["parent"],
        labels
      )
    end

    def require_confirmation(action, prompt, data)
      return nil if @opts[:yes]

      if @opts[:json]
        return json_or_text(action, error: I18n.t("vdnm.errors.confirmation_required"), data: data, code: 1)
      end

      return nil if confirm!(
        "#{UiHelpers.e(:question, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.messages.confirm_continue', prompt: prompt)}"
      )

      json_or_text(action, error: I18n.t("vdnm.errors.cancelled"), data: data, code: 1)
    end

    def disconnect_containers(network_name, containers)
      containers.each do |c|
        say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.disconnect_container', name: c)}"
        Util.sh!("network", "disconnect", "--force", network_name, c)
      end
    end

    def reconnect_containers(network_name, containers, announce: false)
      reconnected      = []
      failed_reconnect = []
      containers.each do |c|
        if Util.sh!("network", "connect", network_name, c)
          reconnected << c
          if announce
            say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.connect_container', name: c, network: network_name)}"
          end
        else
          failed_reconnect << c
        end
      end
      [reconnected, failed_reconnect]
    end

    def network_mode_pinned(network_name, containers)
      containers.select { |c| Util.container_network_mode(c) == network_name }
    end

    def guard_network_mode(action, network_name, containers, data)
      # Containers started with --network=<name> cannot be safely disconnected
      # and reconnected; Docker treats that network as their primary mode.
      pinned = network_mode_pinned(network_name, containers)
      return nil if pinned.empty?

      json_or_text(action,
        error: I18n.t("vdnm.errors.network_mode_pinned", name: network_name, containers: pinned.join(", ")),
        data: data.merge(pinned: pinned), code: 1)
    end

    def json_or_text(action, error: nil, data: {}, code: 0)
      if @opts[:json]
        status = error ? "error" : "success"
        return json_emit(action, status: status, data: data, error: error, code: code)
      end

      if error
        err "#{UiHelpers.e(:error, no_emoji: @opts[:no_emoji])} #{error}"
        return code
      else
        say "#{UiHelpers.e(:success, no_emoji: @opts[:no_emoji])} #{I18n.t('vdnm.log.ok')}" unless @opts[:quiet]
        return 0
      end
    end

    def json_emit(action, status:, data: {}, error: nil, code: 0)
      payload = { action: action, status: status, code: code }
      payload[:data]  = data  unless data.nil? || data.empty?
      payload[:error] = error if error
      puts JSON.generate(payload)
      code
    end

    def say(msg)
      return if @opts[:quiet] || @opts[:json]
      if defined?(@env) && @env && @env.ui
        @env.ui.info(msg)
      else
        puts msg
      end
    end

    def err(msg)
      return if @opts[:json]
      if defined?(@env) && @env && @env.ui
        @env.ui.error(msg)
      else
        warn msg
      end
    end

    def confirm!(prompt)
      return true if @opts[:yes]
      print "#{prompt} "
      ans = $stdin.gets.to_s.strip.downcase
      %w[y yes o oui].include?(ans)
    end
  end
end
