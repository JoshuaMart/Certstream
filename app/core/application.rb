# frozen_string_literal: true

require 'yaml'
require 'logger'
require 'fileutils'
require 'rufus-scheduler'

# Require all files in the app directory
Dir[File.join(__dir__, '..', '**', '*.rb')].sort.each { |file| require file }

module Certstream
  module Core
    class Application
      attr_reader :config, :scheduler

      def initialize
        setup_directories
        load_configuration
        setup_logger
        setup_database
        setup_services
        setup_scheduler
      end

      def start
        # Initial fetch of wildcards
        Core.container.wildcard_fetcher.fetch_wildcards

        # Start the certstream monitor
        Core.container.certstream_monitor.connect_websocket

        # Keep the main thread alive
        begin
          loop do
            sleep 1
          end
        rescue Interrupt
          Core.container.logger.info('Received interrupt signal, shutting down...')
          @scheduler.shutdown
          exit(0)
        end
      end

      private

      def setup_directories
        FileUtils.mkdir_p('logs')
        FileUtils.mkdir_p('data')
      end

      def load_configuration
        @config = YAML.load_file(File.expand_path('../../config/config.yml', __dir__))
      end

      def setup_logger
        logger_file = @config['logging']['file'] || $stdout
        logger_level = Logger.const_get(@config['logging']['level'].upcase || 'INFO')

        logger = Logger.new(logger_file)
        logger.level = logger_level
        logger.formatter = proc do |severity, datetime, _progname, msg|
          "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
        end

        Core.container.register(:logger, logger)
      end

      def setup_database
        database_config = YAML.load_file(File.expand_path('../../config/database.yml', __dir__))
        database = Certstream::Core::Database.new(database_config)
        Core.container.register(:database, database)
      end

      def setup_services
        # Register Discord Notifier
        Core.container.register(:discord_notifier) do
          Certstream::Services::Notification::Discord.new(
            @config['discord']['messages_webhook'],
            @config['discord']['logs_webhook'],
            @config['discord']['username']
          )
        end

        # Register Domain Resolver
        Core.container.register(:domain_resolver) do
          Certstream::Services::Domain::Resolver.new
        end

        # Register Fingerprinter
        Core.container.register(:fingerprinter) do
          Certstream::Services::Notification::Fingerprinter.new(
            @config['fingerprinter']['url'],
            @config['fingerprinter']['callback_url'],
            @config['fingerprinter']['api_key']
          )
        end

        # Register Wildcard Fetcher
        Core.container.register(:wildcard_fetcher) do
          Certstream::Services::Wildcard::Fetcher.new(
            @config['api']['url'],
            @config['api']['headers']
          )
        end

        # Register Wildcard Matcher
        Core.container.register(:wildcard_matcher) do
          Certstream::Services::Wildcard::Matcher.new
        end

        # Register Certstream Monitor
        Core.container.register(:certstream_monitor) do
          Certstream::Services::Certstream::Monitor.new(
            @config['certstream']['url'],
            @config['certstream']['exclusions'],
            @config['concurrency']['min'],
            @config['concurrency']['max']
          )
        end
      end

      def setup_scheduler
        @scheduler = Rufus::Scheduler.new

        # Setup wildcard fetch job
        @scheduler.every "#{@config['api']['update_interval']}s" do
          Core.container.logger.info('Scheduled fetch of wildcards')
          Core.container.wildcard_fetcher.fetch_wildcards
        end

        # Setup domain resolution retry job
        @scheduler.every "#{@config['database']['retry_interval']}s" do
          Core.container.logger.info('Starting scheduled retry of unresolvable domains')
          job = Certstream::Jobs::RetryUnresolvableDomainsJob.new(
            @config['database']['max_retries']
          )
          job.perform
        end
      end
    end
  end
end
