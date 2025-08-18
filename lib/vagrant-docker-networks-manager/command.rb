# frozen_string_literal: true

require "json"
require "ipaddr"
require "open3"
require "optparse"
require "ostruct"
require_relative "network_builder"
require_relative "helpers"
require_relative "util"
require_relative "version"

module VagrantDockerNetworksManager
  class Command < Vagrant.plugin("2", :command)
    def execute
      argv = @argv.dup
      @opts = { quiet: false, no_emoji: false, json: false, yes: false, lang: nil, with_containers: false }

      UiHelpers.setup_i18n!

      OptionParser.new do |o|
        o.on("--quiet", "Reduce output (hide info)")               { @opts[:quiet] = true }
        o.on("--no-emoji", "Disable emojis in output")             { @opts[:no_emoji] = true }
        o.on("--json", "Normalized JSON output for all commands")  { @opts[:json] = true }
        o.on("--yes", "-y", "Auto-confirm destructive operations") { @opts[:yes] = true }
        o.on("--lang LANG", "Force language: en|fr")               { |v| @opts[:lang] = v }
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
        msg = "#{UiHelpers.e(:error, no_emoji: @opts[:no_emoji])} #{I18n.t('errors.docker_unavailable')}"
        return json_or_text("precheck", error: msg, code: 2)
      end

      case subcmd
      when "init"
        return json_or_text("init", error: I18n.t("usage.init"), code: 1) if argv.length < 3
        return json_or_text(
          'init',
          error: I18n.t('errors.network_exists'),
          data: { name: network_name },
          code: 1
        ) if Util.docker_network_exists?(network_name)
        return json_or_text(
          'init',
          error: I18n.t('errors.invalid_subnet'),
          data: { name: subnet },
          code: 1
        ) unless Util.valid_subnet?(subnet)
        return json_or_text(
          'init',
          error: I18n.t('errors.subnet_in_use'),
          data: { name: subnet },
          code: 1
        ) if Util.docker_subnet_conflicts?(subnet)
        return json_or_text("init",
          error: I18n.t("errors.invalid_name"),
          data: { name: network_name },
          code: 1
        ) unless network_name =~ /\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,126}\z/
        cfg = OpenStruct.new(
          network_name: network_name,
          network_type: "bridge",
          network_subnet: subnet,
          network_gateway: nil,
          network_parent: nil,
          network_attachable: false,
          enable_ipv6: false,
          ip_range: nil
        )
        args = NetworkBuilder.new(cfg).build_create_command_args
        say "#{UiHelpers.e(:ongoing,
no_emoji: @opts[:no_emoji])} #{I18n.t('log.create_network', name: network_name, subnet: subnet)}"
        ok = Util.sh!(*args)
        if ok
          json_or_text("init", data: { name: network_name, subnet: subnet })
        else
          json_or_text(
            'init',
            error: I18n.t("errors.create_failed"),
            data: { name: network_name, subnet: subnet },
          code: 1)
        end

      when "destroy"
        return json_or_text("destroy", error: I18n.t("usage.destroy"), code: 1) if argv.length < 2
        return json_or_text("destroy", error: I18n.t("errors.network_not_found"), data: { name: network_name },
code: 1) unless Util.docker_network_exists?(network_name)

        out, _e, st = Open3.capture3("docker", "network", "inspect", network_name)
        containers = []
        if st.success?
          j = JSON.parse(out).first
          containers = (j["Containers"] || {}).values.map { |c| c["Name"] }
        end

        prompt_key = @opts[:with_containers] ? "prompts.delete_network_with_containers" : "prompts.delete_network_only"
        prompt_msg = I18n.t(prompt_key, name: network_name, count: containers.size)
        unless @opts[:yes] || @opts[:json] || confirm!(
          "#{UiHelpers.e(:question,
no_emoji: @opts[:no_emoji])} #{I18n.t('messages.confirm_continue', prompt: prompt_msg)}"
        )
          return json_or_text("destroy", error: I18n.t("errors.cancelled"), data: { name: network_name }, code: 1)
        end

        containers.each do |c|
          say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('log.disconnect_container', name: c)}"
          Util.sh!("network", "disconnect", "--force", network_name, c)
          if @opts[:with_containers]
            say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('log.remove_container', name: c)}"
            Util.sh!("rm", "-f", c)
          end
        end

        say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('log.remove_network', name: network_name)}"
        ok = Util.sh!("network", "rm", network_name)
        if ok
          json_or_text("destroy",
data: { name: network_name, removed_containers: (@opts[:with_containers] ? containers : []) })
        else
          json_or_text("destroy", error: I18n.t("errors.remove_failed"),
            data: { name: network_name, removed_containers: (@opts[:with_containers] ? containers : []) }, code: 1)
        end

      when "info"
        return json_or_text("info", error: I18n.t("usage.info"), code: 1) if argv.length < 2
        return json_or_text("info", error: I18n.t("errors.network_not_found"), data: { name: network_name },
code: 1) unless Util.docker_network_exists?(network_name)

        out, _e, st = Open3.capture3("docker", "network", "inspect", network_name)
        return json_or_text("info", error: I18n.t("errors.inspect_failed"), data: { name: network_name },
code: 1) unless st.success?
        info = JSON.parse(out).first

        if @opts[:json]
          payload = {
            network: {
              "Name" => info["Name"],
              "Id" => info["Id"],
              "Driver" => info["Driver"],
              "Subnets" => (info.dig("IPAM","Config") || []).map { |c| c["Subnet"] }.compact,
              "Containers" => (info["Containers"] || {}).values.map do |c|
                { "Name" => c["Name"], "IPv4" => c["IPv4Address"] }
              end
            }
          }
          return json_emit("info", status: "success", data: payload)
        end

        say "#{UiHelpers.e(:info, no_emoji: @opts[:no_emoji])} #{I18n.t('log.info_header', name: network_name)}"
        puts "  • ID: #{info['Id'][0...12]}"
        puts "  • Driver: #{info['Driver']}"
        puts "  • Subnet(s): #{(info.dig('IPAM','Config') || []).map { |c| c['Subnet'] }.compact.join(', ')}"
        cons = info["Containers"] || {}
        if cons.empty?
          puts "  • Connected containers: (none)"
        else
          puts "  • Connected containers:"
          cons.each_value { |c| puts "    • #{c['Name']} (IP: #{c['IPv4Address']})" }
        end
        0

      when "reload"
        return json_or_text("reload", error: I18n.t("usage.reload"), code: 1) if argv.length < 2

        name = network_name
        return json_or_text("reload", error: I18n.t("errors.network_not_found"), data: { name: name },
code: 1) unless Util.docker_network_exists?(name)

        out, _e, st = Open3.capture3("docker", "network", "inspect", name)
        return json_or_text("reload", error: I18n.t("errors.inspect_failed"), data: { name: name },
code: 1) unless st.success?
        info = JSON.parse(out).first

        driver      = info["Driver"] || "bridge"
        ipam_cfgs   = (info.dig("IPAM","Config") || [])
        subnets     = ipam_cfgs.map { |c| c["Subnet"] }.compact
        containers  = (info["Containers"] || {}).values.map { |c| c["Name"] }
        enable_ipv6 = info["EnableIPv6"]
        attachable  = info["Attachable"]
        parent_opt  = info.fetch("Options", {})["parent"]
        labels_h    = info["Labels"] || {}
        labels_h["com.vagrant.plugin"] ||= "docker_networks_manager"

        unless ENV["VDNM_SKIP_CONFLICTS"] == "1"
          has_conflict = subnets.any? { |s| Util.docker_subnet_conflicts?(s, ignore_network: name) }
          if has_conflict
            return json_or_text("reload",
              error: I18n.t("errors.subnet_in_use"),
              data: { name: name, subnets: subnets }, code: 1)
          end
        end

        unless @opts[:yes] || @opts[:json] || confirm!(
          "#{UiHelpers.e(:question,
no_emoji: @opts[:no_emoji])} #{I18n.t('messages.confirm_continue', prompt: I18n.t('prompts.reload_same', name: name))}"
        )
          return json_or_text("reload", error: I18n.t("errors.cancelled"), data: { name: name }, code: 1)
        end

        containers.each do |c|
          say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('log.disconnect_container', name: c)}"
          Util.sh!("network", "disconnect", "--force", name, c)
        end

        say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('log.remove_network', name: name)}"
        ok_rm = Util.sh!("network", "rm", name)
        unless ok_rm
          return json_or_text("reload", error: I18n.t("errors.remove_failed"), data: { name: name }, code: 1)
        end

        args = ["network", "create", "--driver", driver]
        labels_h.each { |k,v| args += ["--label", "#{k}=#{v}"] if k && v }
        ipam_cfgs.each do |c|
          args += ["--subnet",   c["Subnet"]]   if c["Subnet"]
          args += ["--gateway",  c["Gateway"]]  if c["Gateway"]
          args += ["--ip-range", c["IPRange"]]  if c["IPRange"]
        end
        args << "--ipv6"       if enable_ipv6
        args << "--attachable" if attachable
        args += ["--opt", "parent=#{parent_opt}"] if parent_opt && driver == "macvlan"
        say "#{UiHelpers.e(:ongoing,
no_emoji: @opts[:no_emoji])} #{I18n.t('log.create_network', name: name,
subnet: (subnets.empty? ? "-" : subnets.join(', ')))}"
        ok_cr = Util.sh!(*args, name)
        unless ok_cr
          rendered = (["docker"] + args + [name]).map(&:to_s).shelljoin
          return json_or_text("reload", error: "#{I18n.t('errors.create_failed')} (#{rendered})",
data: { name: name, subnets: subnets }, code: 1)
        end

        reconnected = []
        failed_reconnect = []
        containers.each do |c|
          if Util.sh!("network", "connect", name, c)
            reconnected << c
          else
            failed_reconnect << c
          end
        end

        data = { name: name, subnets: subnets, reconnected: reconnected, failed_reconnect: failed_reconnect }
        if failed_reconnect.any?
          json_or_text("reload", error: I18n.t("errors.partial_failure"), data: data, code: 1)
        else
          json_or_text("reload", data: data)
        end
      when "prune"
        nets = Util.list_plugin_networks_detailed
        to_delete = nets.select { |n| n[:containers].to_i == 0 }

        if to_delete.empty?
          if @opts[:json]
            return json_emit("prune", status: "success", data: { pruned: 0, items: [] })
          else
            say "#{UiHelpers.e(:info, no_emoji: @opts[:no_emoji])} #{I18n.t('messages.prune_none')}"
            return 0
          end
        end

        unless @opts[:yes] || @opts[:json] || confirm!(
          "#{UiHelpers.e(:question,
no_emoji: @opts[:no_emoji])} #{I18n.t('messages.confirm_continue',
prompt: I18n.t('prompts.prune', count: to_delete.size))}"
        )
          return json_or_text("prune", error: I18n.t("errors.cancelled"), data: { candidates: to_delete.map do |n|
            n[:name]
          end }, code: 1)
        end

        ok_all = true
        to_delete.each do |n|
          say "#{UiHelpers.e(:ongoing,
no_emoji: @opts[:no_emoji])} #{I18n.t('log.remove_network', name: n[:name])}" unless @opts[:quiet]
          ok_all &&= Util.sh!("network", "rm", n[:name])
        end

        if ok_all
          json_or_text("prune", data: { pruned: to_delete.size, items: to_delete.map { |n| n[:name] } })
        else
          json_or_text("prune", error: I18n.t("errors.partial_failure"), data: { attempted: to_delete.map do |n|
            n[:name]
          end }, code: 1)
        end

      when "list"
        nets = Util.list_plugin_networks
        if @opts[:json]
          return json_emit("list", status: "success", data: { count: nets.size, items: nets })
        end

        if nets.empty?
          say "#{UiHelpers.e(:info, no_emoji: @opts[:no_emoji])} #{I18n.t('messages.no_networks')}"
          return 0
        end

        say "#{UiHelpers.e(:info, no_emoji: @opts[:no_emoji])} #{I18n.t('messages.networks_header')}"
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
        ].join('  ')
        puts "  #{header_line}"
        puts "  #{'-' * name_w}  #{'-' * driver_w}  #{'-' * scope_w}  #{'-' * subnet_w}"

        nets.sort_by { |r| r[:name] }.each do |r|
          puts "  %-#{name_w}s  %-#{driver_w}s  %-#{scope_w}s  %s" % [r[:name], r[:driver], r[:scope], r[:subnets]]
        end
        0

      when "rename"
        return json_or_text("rename", error: I18n.t("usage.rename"), code: 1) if argv.length < 3

        old_name   = argv[1]
        new_name   = argv[2]
        new_subnet = argv[3]

        return json_or_text("rename", error: I18n.t("errors.network_not_found"), data: { old: old_name },
code: 1) unless Util.docker_network_exists?(old_name)
        if new_name != old_name && Util.docker_network_exists?(new_name)
          return json_or_text("rename", error: I18n.t("errors.target_exists"), data: { new: new_name }, code: 1)
        end

        o, _e, st = Open3.capture3("docker", "network", "inspect", old_name)
        return json_or_text("rename", error: I18n.t("errors.inspect_failed"), data: { old: old_name },
code: 1) unless st.success?
        j = JSON.parse(o).first
        driver       = j["Driver"] || "bridge"
        old_subnets  = (j.dig("IPAM","Config") || []).map { |c| c["Subnet"] }.compact
        containers   = (j["Containers"] || {}).values.map { |c| c["Name"] }
        enable_ipv6  = j["EnableIPv6"]
        attachable   = j["Attachable"]
        parent_opt   = j.fetch("Options", {})["parent"]
        labels_h     = j["Labels"] || {}
        labels_h["com.vagrant.plugin"] ||= "docker_networks_manager"

        target_subnet = new_subnet || old_subnets.first
        return json_or_text("rename", error: I18n.t("errors.invalid_subnet"), data: { subnet: target_subnet },
code: 1) unless Util.valid_subnet?(target_subnet)

        old_norms   = old_subnets.map { |s| Util.normalize_cidr(s) }.compact
        target_norm = Util.normalize_cidr(target_subnet)
        same_subnet = old_norms.include?(target_norm)

        if !same_subnet && Util.docker_subnet_conflicts?(target_subnet, ignore_network: old_name)
          return json_or_text("rename", error: I18n.t("errors.subnet_in_use"), data: { subnet: target_subnet }, code: 1)
        end

        prompt_msg =
          if new_name == old_name && same_subnet
            I18n.t("prompts.reload_same", name: old_name)
          elsif new_name == old_name && !same_subnet
            I18n.t("prompts.reload_network", name: old_name)
          elsif same_subnet
            I18n.t("prompts.rename_same_subnet", old: old_name, new: new_name)
          else
            I18n.t("prompts.rename_network", old: old_name, new: new_name)
          end
        unless @opts[:yes] || @opts[:json] || confirm!(
          "#{UiHelpers.e(:question,
no_emoji: @opts[:no_emoji])} #{I18n.t('messages.confirm_continue', prompt: prompt_msg)}"
        )
          return json_or_text("rename", error: I18n.t("errors.cancelled"), data: { old: old_name, new: new_name },
code: 1)
        end

        reconnected = []
        failed_reconnect = []

        create_with_retry = lambda do |name_to_create, subnet_to_use|
          say "#{UiHelpers.e(:ongoing,
no_emoji: @opts[:no_emoji])} #{I18n.t('log.create_network', name: name_to_create, subnet: subnet_to_use)}"
          args = ["network", "create", "--driver", driver, "--subnet", subnet_to_use]
          labels_h.each { |k,v| args += ["--label", "#{k}=#{v}"] if k && v }
          args << "--ipv6"       if enable_ipv6
          args << "--attachable" if attachable
          args += ["--opt", "parent=#{parent_opt}"] if parent_opt && driver == "macvlan"
          ok = Util.sh!(*args, name_to_create)
          unless ok
            rendered = (["docker"] + args + [name_to_create]).map(&:to_s).shelljoin
            err("#{UiHelpers.e(:error, no_emoji: @opts[:no_emoji])} #{I18n.t('errors.create_failed')} (#{rendered})")
          end
          ok
        end

        if new_name == old_name || same_subnet
          target_name = new_name

          containers.each do |c|
            say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('log.disconnect_container', name: c)}"
            Util.sh!("network", "disconnect", "--force", old_name, c)
          end

          say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('log.remove_network', name: old_name)}"
          ok_rm = Util.sh!("network", "rm", old_name)
          return json_or_text("rename", error: I18n.t("errors.remove_failed"), data: { name: old_name },
code: 1) unless ok_rm

          ok_cr = create_with_retry.call(target_name, target_subnet)
          return json_or_text("rename", error: I18n.t("errors.create_failed"),
data: { new: target_name, subnet: target_subnet }, code: 1) unless ok_cr

          containers.each do |c|
            if Util.sh!("network", "connect", target_name, c)
              reconnected << c
            else
              failed_reconnect << c
            end
          end
        else
          ok_cr = create_with_retry.call(new_name, target_subnet)
          return json_or_text("rename", error: I18n.t("errors.create_failed"),
data: { new: new_name, subnet: target_subnet }, code: 1) unless ok_cr

          containers.each do |c|
            if Util.sh!("network", "connect", new_name, c)
              reconnected << c
              say "#{UiHelpers.e(:ongoing,
no_emoji: @opts[:no_emoji])} #{I18n.t('docker_provider.network_connect')} #{c} -> #{new_name}"
            else
              failed_reconnect << c
            end
          end

          reconnected.each do |c|
            say "#{UiHelpers.e(:ongoing,
no_emoji: @opts[:no_emoji])} #{I18n.t('log.disconnect_container', name: c)} <- #{old_name}"
            Util.sh!("network", "disconnect", "--force", old_name, c)
          end

          say "#{UiHelpers.e(:ongoing, no_emoji: @opts[:no_emoji])} #{I18n.t('log.remove_network', name: old_name)}"
          ok_rm = Util.sh!("network", "rm", old_name)
          unless ok_rm
            error_data = {
              old: old_name,
              new: new_name,
              subnet: target_subnet,
              reconnected: reconnected,
              failed_reconnect: failed_reconnect
            }
            return json_or_text('rename', error: I18n.t('errors.remove_failed'), data: error_data, code: 1)
          end
        end

        result_data = {
           old: old_name,
           new: new_name,
           subnet: target_subnet,
           reconnected: reconnected,
           failed_reconnect: failed_reconnect
        }

        if failed_reconnect.any?
          json_or_text("rename", error: I18n.t("errors.partial_failure"), data: result_data, code: 1)
        else
          json_or_text("rename", data: result_data)
        end

      when "version"
        if @opts[:json]
          return json_emit("version", status: "success", data: { version: VagrantDockerNetworksManager::VERSION })
        end
        say "#{UiHelpers.e(:version, no_emoji: @opts[:no_emoji])} #{I18n.t('log.version_line', version: VagrantDockerNetworksManager::VERSION)}"
        0

      when "help"
        VagrantDockerNetworksManager::UiHelpers.print_topic_help(argv[1])
        0

      else
        return json_or_text("unknown", error: I18n.t("errors.unknown_command"), code: 1)
      end
    end

    private

    def json_or_text(action, error: nil, data: {}, code: 0)
      if @opts[:json]
        status = error ? "error" : "success"
        return json_emit(action, status: status, data: data, error: error, code: code)
      end

      if error
        err "#{UiHelpers.e(:error, no_emoji: @opts[:no_emoji])} #{error}"
        return code
      else
        say "#{UiHelpers.e(:success, no_emoji: @opts[:no_emoji])} #{I18n.t('log.ok')}" unless @opts[:quiet]
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
