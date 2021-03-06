require 'erb'
require 'yaml'
require 'appsignal/integrations/capistrano/careful_logger'

module Appsignal
  class Config
    include Appsignal::CarefulLogger

    DEFAULT_CONFIG = {
      :ignore_exceptions => [],
      :ignore_actions => [],
      :send_params => true,
      :endpoint => 'https://push.appsignal.com/1',
      :slow_request_threshold => 200,
      :instrument_net_http => true
    }.freeze

    attr_reader :root_path, :env, :initial_config, :config_hash

    def initialize(root_path, env, initial_config={}, logger=Appsignal.logger)
      @root_path = root_path
      @env = env.to_s
      @initial_config = initial_config
      @logger = logger

      if File.exists?(config_file)
        load_config_from_disk
      elsif ENV['APPSIGNAL_PUSH_API_KEY']
        load_default_config_with_push_api_key(
          ENV['APPSIGNAL_PUSH_API_KEY']
        )
      elsif ENV['APPSIGNAL_API_KEY']
        load_default_config_with_push_api_key(
          ENV['APPSIGNAL_API_KEY']
        )
        @logger.info(
          'The APPSIGNAL_API_KEY environment variable has been deprecated, ' \
          'please switch to APPSIGNAL_PUSH_API_KEY'
        )
      else
        carefully_log_error(
          "Not loading: No config file found at '#{config_file}' " \
          "and no APPSIGNAL_PUSH_API_KEY env var present"
        )
      end
    end

    def loaded?
      !! config_hash
    end

    def [](key)
      return unless loaded?
      config_hash[key]
    end

    def active?
      !! self[:active]
    end

    protected

    def config_file
      @config_file ||= File.join(root_path, 'config', 'appsignal.yml')
    end

    def load_config_from_disk
      configurations = YAML.load(ERB.new(IO.read(config_file)).result)
      config_for_this_env = configurations[env]
      if config_for_this_env
        config_for_this_env = Hash[config_for_this_env.map do |key, value|
          [key.to_sym, value]
        end] # convert keys to symbols

        # Backwards compatibility with config files generated by earlier
        # versions of the gem
        if !config_for_this_env[:push_api_key] && config_for_this_env[:api_key]
          config_for_this_env[:push_api_key] = config_for_this_env[:api_key]
        end

        @config_hash = merge_config(config_for_this_env)
      else
        carefully_log_error("Not loading: config for '#{env}' not found")
      end
    end

    def load_default_config_with_push_api_key(key)
      @config_hash = merge_config(
        :push_api_key => key,
        :active => true
      )
    end

    def merge_config(config)
      DEFAULT_CONFIG.merge(initial_config).merge(config)
    end
  end
end
