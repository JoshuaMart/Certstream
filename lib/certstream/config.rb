# frozen_string_literal: true

require 'yaml'

module Certstream
  class Config
    DEFAULT_CONFIG_PATH = 'config.yml'

    attr_reader :data

    def initialize(path = nil)
      @path = path || DEFAULT_CONFIG_PATH
      @data = load_config
    end

    def certstream
      @data['certstream']
    end

    def apis
      @data['apis'].reject { |api| api['enabled'] == false }
    end

    def wildcards_update_interval
      @data['wildcards_update_interval']
    end

    def http
      @data['http']
    end

    def fingerprinter
      @data['fingerprinter']
    end

    def discord
      @data['discord']
    end

    def logging
      @data['logging']
    end

    def shutdown
      @data['shutdown']
    end

    private

    def load_config
      raise ConfigError, "Configuration file not found: #{@path}" unless File.exist?(@path)

      YAML.safe_load_file(@path, permitted_classes: [Symbol]) || {}
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML syntax in #{@path}: #{e.message}"
    end
  end

  class ConfigError < StandardError; end
end
