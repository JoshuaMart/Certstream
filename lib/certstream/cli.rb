# frozen_string_literal: true

require 'thor'

module Certstream
  class CLI < Thor
    desc 'start', 'Start the Certstream monitor'
    option :config, type: :string, aliases: '-c', default: 'config.yml', desc: 'Path to configuration file'
    option :log_level, type: :string, aliases: '-l', desc: 'Log level (DEBUG, INFO, WARN, ERROR, FATAL)'
    def start
      config = build_config
      logger = build_logger(config)
      run_monitor(config, logger)
    rescue ConfigError => e
      puts "Configuration error: #{e.message}".red
      exit 1
    rescue Interrupt
      puts "\nShutting down...".yellow
      exit 0
    end

    desc 'version', 'Display version'
    def version
      puts "Certstream Monitor v#{VERSION}"
    end

    def self.exit_on_failure?
      true
    end

    private

    def build_config
      config = Config.new(options[:config])
      config.data['logging']['level'] = options[:log_level].upcase if options[:log_level]
      config
    end

    def build_logger(config)
      logger = Certstream::Logger.new(config.logging)
      logger.info('CLI', "Starting Certstream Monitor v#{VERSION}")
      logger
    end

    def run_monitor(config, logger)
      Monitor.new(config, logger).run
    end
  end
end
