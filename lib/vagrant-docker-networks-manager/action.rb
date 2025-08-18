# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require "shellwords"
require "open3"
require_relative "helpers"
require_relative "util"
require_relative "network_builder"
require_relative "version"

module VagrantDockerNetworksManager
  class ActionUp
    def initialize(app, _env); @app = app; end

    def call(env)
      UiHelpers.setup_i18n!
      cfg  = env[:machine].config.docker_network
      set_locale!(cfg)

      unless Util.docker_available?
        env[:ui].error("#{UiHelpers.e(:error)} #{I18n.t('errors.docker_unavailable')}")
        return @app.call(env)
      end

      name = cfg.network_name
      mid  = env[:machine].id

      if Util.docker_network_exists?(name)
        if owned_by_this_machine?(name, mid)
          write_marker(env, name, cfg)
          env[:ui].info("#{UiHelpers.e(:success)} #{I18n.t('messages.network_exists_adopted', name: name)}")
        else
          env[:ui].info("#{UiHelpers.e(:info)} #{I18n.t('messages.network_exists', name: name)}")
        end
      else
        subnet_label = cfg.network_subnet || "-"

        if cfg.network_subnet && !VagrantDockerNetworksManager::Util.valid_subnet?(cfg.network_subnet)
          env[:ui].error("#{UiHelpers.e(:error)} #{I18n.t('errors.invalid_subnet')}")
          return @app.call(env)
        end

        if cfg.network_subnet &&
           VagrantDockerNetworksManager::Util.docker_subnet_conflicts?(
             cfg.network_subnet,
             ignore_network: name
           )
          env[:ui].error("#{UiHelpers.e(:error)} #{I18n.t('errors.subnet_in_use')}")
          return @app.call(env)
        end

        env[:ui].info("#{UiHelpers.e(:ongoing)} #{I18n.t('log.create_network', name: name, subnet: subnet_label)}")
        builder = NetworkBuilder.new(cfg, machine_id: mid)
        args = builder.build_create_command_args
        if Util.sh!(*args)
          write_marker(env, name, cfg)
          env[:ui].info("#{UiHelpers.e(:success)} #{I18n.t('log.ok')}")
        else
          rendered = args.shelljoin
          env[:ui].error("#{UiHelpers.e(:error)} #{I18n.t('messages.create_failed', cmd: rendered)}")
        end
      end

      @app.call(env)
    end

    private

    def set_locale!(cfg)
      lang = cfg.locale || ENV["VDNM_LANG"]
      return unless lang
      UiHelpers.set_locale!(lang)
    rescue UiHelpers::UnsupportedLocaleError
      UiHelpers.set_locale!("en")
    end

    def write_marker(env, name, cfg)
      m_id  = env[:machine].id
      dir   = env[:machine].data_dir.join("docker-networks")
      FileUtils.mkdir_p(dir)
      marker = dir.join("#{name}.json")
      payload = {
        "name"         => name,
        "machine_id"   => m_id,
        "plugin"       => "vagrant-docker-networks-manager",
        "version"      => VagrantDockerNetworksManager::VERSION,
        "created_at"   => Time.now.utc.iso8601,
        "config"       => {
          "type"        => cfg.network_type,
          "subnet"      => cfg.network_subnet,
          "gateway"     => cfg.network_gateway,
          "ip_range"    => cfg.ip_range,
          "ipv6"        => !!cfg.enable_ipv6,
          "attachable"  => !!cfg.network_attachable,
          "parent"      => cfg.network_parent
        }
      }
      File.write(marker, JSON.pretty_generate(payload))
    rescue => e
      env[:ui].warn("marker write failed for '#{name}': #{e.message}")
    end

    def owned_by_this_machine?(name, machine_id)
      labels = Util.read_network_labels(name)
      labels["com.vagrant.plugin"] == "docker_networks_manager" &&
        labels["com.vagrant.machine_id"] == machine_id
    end
  end

  class ActionDestroy
    def initialize(app, _env); @app = app; end

    def call(env)
      UiHelpers.setup_i18n!
      cfg  = env[:machine].config.docker_network
      set_locale!(cfg)

      unless Util.docker_available?
        env[:ui].error("#{UiHelpers.e(:error)} #{I18n.t('errors.docker_unavailable')}")
        return @app.call(env)
      end

      name = cfg.network_name
      mid  = env[:machine].id

      unless cfg.cleanup_on_destroy
        @app.call(env)
        return
      end

      if created_by_this_machine?(env, name) || owned_by_this_machine?(name, mid)
        env[:ui].info("#{UiHelpers.e(:broom)} #{I18n.t('messages.remove_network', name: name)}")

        if Util.docker_network_exists?(name)
          out, _e, st = Open3.capture3("docker", "network", "inspect", name)
          if st.success?
            begin
              info = JSON.parse(out).first
              (info["Containers"] || {}).values.each do |c|
                cn = c["Name"]
                env[:ui].info("#{UiHelpers.e(:ongoing)} #{I18n.t('log.disconnect_container', name: cn)}")
                Util.sh!("network", "disconnect", "--force", name, cn)
                if ENV["VDNM_DESTROY_WITH_CONTAINERS"] == "1"
                  env[:ui].info("#{UiHelpers.e(:ongoing)} #{I18n.t('log.remove_container', name: cn)}")
                  Util.sh!("rm", "-f", cn)
                end
              end
            rescue => e
              env[:ui].warn("failed to parse containers for '#{name}': #{e.message}")
            end
          end

          if Util.sh!("network", "rm", name)
            delete_marker(env, name)
            env[:ui].info("#{UiHelpers.e(:success)} #{I18n.t('log.ok')}")
          else
            env[:ui].warn("#{UiHelpers.e(:warning)} #{I18n.t('errors.remove_failed')}")
          end
        else
          delete_marker(env, name)
          env[:ui].info("#{UiHelpers.e(:info)} #{I18n.t('messages.nothing_to_do')}")
        end
      else
        env[:ui].info("#{UiHelpers.e(:broom)} #{I18n.t('messages.nothing_to_do')}")
      end

      @app.call(env)
    end

    private

    def set_locale!(cfg)
      lang = cfg.locale || ENV["VDNM_LANG"]
      return unless lang
      UiHelpers.set_locale!(lang)
    rescue UiHelpers::UnsupportedLocaleError
      UiHelpers.set_locale!("en")
    end

    def marker_path(env, name)
      env[:machine].data_dir.join("docker-networks", "#{name}.json")
    end

    def created_by_this_machine?(env, name)
      marker = marker_path(env, name)
      return false unless File.exist?(marker)
      j = JSON.parse(File.read(marker)) rescue {}
      j["name"] == name && j["machine_id"] == env[:machine].id
    end

    def owned_by_this_machine?(name, machine_id)
      labels = Util.read_network_labels(name)
      labels["com.vagrant.plugin"] == "docker_networks_manager" &&
        labels["com.vagrant.machine_id"] == machine_id
    end

    def delete_marker(env, name)
      m = marker_path(env, name)
      File.delete(m) if File.exist?(m)
    end
  end
end
