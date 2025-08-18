# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "stringio"
require "tmpdir"
require "ostruct"

unless defined?(Vagrant)
  module Vagrant
    def self.plugin(_version, type)
      case type
      when :config
        Class.new do
          const_set(:UNSET_VALUE, :__UNSET__.freeze)
        end
      when :command
        Class.new do
          def initialize(argv, env)
            @argv = argv
            @env  = env
          end
        end
      else
        Class.new
      end
    end

    class Environment; end

    module Util
      module Platform
        def self.windows? = false
      end
    end
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

def capture_io
  old_out, old_err = $stdout, $stderr
  out, err = StringIO.new, StringIO.new
  $stdout, $stderr = out, err
  result = yield
  [out.string, err.string, result]
ensure
  $stdout, $stderr = old_out, old_err
end
